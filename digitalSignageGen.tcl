package require sha256
package require base64
package require http
package require json

if {[catch {package require twapi_crypto}]} {
    package require tls
    http::register https 443 [list ::tls::socket -tls1 1]
} else {
    http::register https 443 [list ::twapi::tls_socket]
}

proc isDict {value} {
    return [expr {[string is list $value] && ([llength $value]&1) == 0}]
}

proc getAPItoken {key secret} {
    set offset 1
    set base "https://api.communico.co/v3"
    set auth [::base64::encode -maxlen 0 ${key}:${secret}]
    set header [list Authorization "Basic ${auth}"]
    set token [::http::geturl ${base}/token -headers $header -query "grant_type=client_credentials"]
    set response [::http::data $token]
    set response [split $response {\"}]
    set accessType [lindex $response 9]
    set accessToken [lindex $response 3]
    puts "Successfully logged in to Communico"
    return $accessToken
}

proc getAPIresult {URL accessToken} {
    set base "https://api.communico.co/v3"
    set header [list Authorization "Bearer ${accessToken}" User-Agent "LibraryTEST"]
    set token [::http::geturl ${base}/${URL} -headers $header -method GET]
    set response [::http::data $token]
    set json [::json::json2dict $response]
    set result [dict get $json data]
    return $result
}

proc getEventInfo {eventId lookupValue accessToken} {
    set matchingEvent [getAPIresult attend/events/${eventId}?fields=shortDescription,privateEvent,types,setupTime,breakdownTime,status,ages,modified $accessToken]
    if {[dict exists $matchingEvent $lookupValue]} {
        return [dict get $matchingEvent $lookupValue]
    } else  {
        return {}
    }   
}

proc getEventTime {start end} {
    set start [string map {"12:00 pm" "Noon"} $start]
    set end [string map {"12:00 pm" "Noon"} $end]
    if {[string first " " $start] == 0} {
        set start [string trimleft $start " "]
    }
    if {[string first " " $end] == 0} {
        set end [string trimleft $end " "]
    }
    if {[string first pm $start] != -1 && [string first pm $end] != -1} {
        set start [string map {" pm" ""} $start]
    }
    if {[string first am $start] != -1 && [string first am $end] != -1} {
        set start [string map {" am" ""} $start]
    }
    set times "${start}-${end}"
    set times [string map {"am-" "am - "} $times]
    set times [string map {"am" "a.m."} $times]
    set times [string map {"pm" "p.m."} $times]
    set times [string map {":00" ""} $times]
    return $times
}

proc getLocation {locationName roomName} {
    if {[string first Central $locationName] != -1 || [string first Fountain $locationName] != -1 } {
        set location $roomName
    } else  {
        set location $locationName
    }
    return $location
}

if {![file exists config.ini]} {
    puts "Config file is missing!"
    exit
}
set config [open config.ini r]
set config [read -nonewline $config]
if {![isDict $config]} {
    puts "Config file is invalid!"
    exit
}
if {![dict exist $config key] || ![dict exist $config secret] || ![dict exist $config average] || ![dict exist $config start]} {
    puts "Required config option(s) missing!"
    exit
}

set key [dict get $config key]
set secret [dict get $config secret]
set average [dict get $config average]
set start "0.[dict get $config start]"

set accessToken [getAPItoken $key $secret]

#There is no way to pick specific dates or date ranges when looking up room bookings
#Since we require patron bookings to be included, we must somehow find the days we are looking for
#This will sweep over all bookings, starting 75% through the total number of bookings, to find today's bookings
#The sweep is fairly fast due to going quickly until we get closer to today's bookings
#the sweep method is based upon the average number of bookings per day and may need to be adjusted
set total [dict get [getAPIresult reserve/reservations?start=${average}&limit=1 $accessToken] total]
set startID [expr round([expr {$total * $start}])]
set sweep [expr {$average * 16}]
set failed 0
while {$failed < 100} {
    set startSearch [getAPIresult reserve/reservations?start=${startID}&limit=1 $accessToken]
    foreach id [dict get $startSearch entries] {
        dict with id {
            set recordUnixTime [clock scan $startTime -format "%Y-%m-%d %H:%M:%S"]
            
        }
    }
    if {[dict exists $startSearch entries]} {
        set currentUnixTime [clock seconds]
        if {($currentUnixTime - $recordUnixTime) < 9676800} {
            #112
            set sweep [expr {$average * 8}]
        }
        if {($currentUnixTime - $recordUnixTime) < 4838400} {
            #56
            set sweep [expr {$average * 4}]
        }
        if {($currentUnixTime - $recordUnixTime) < 2419200} {
            #28
            set sweep [expr {$average * 2}]
        }
        if {($currentUnixTime - $recordUnixTime) < 1209600} {
            #14
            set sweep $average
        }
        if {($currentUnixTime - $recordUnixTime) < 604800} {
            #7
            set begin [expr {$startID + 0}]
            puts "Starting at eventID $begin after $failed attempts at finding today's data"
            break
        }
        puts "Checking date of eventID $startID"
        set startID [expr {$startID + $sweep}]
        incr failed
    }
}

set prettyDate [string toupper [clock format [clock seconds] -format "%A, %B %d"]]
set currentDate [clock format [clock seconds] -format "%Y-%m-%d"]
set currentStamp [clock seconds]
set rooms [getAPIresult reserve/rooms $accessToken]
set locationMap [dict create]
foreach item [dict get $rooms entries] {
    dict with item {
        dict set locationMap $roomId $name
    }
}
set bookings [getAPIresult reserve/reservations?start=${begin}&limit=700&status=approved&fields=eventId,locationName,type $accessToken]
set events [getAPIresult attend/events?start=0&limit=5&privateEvents=false&status=published&startDate=${currentDate}&endDate=${currentDate}&types=Bus%20Trips $accessToken]

#Loop over every room and generate file for that room
foreach habitation [dict get $rooms entries] {
    dict with habitation {
        set fileName [string map {" " "" "#" "" "/" "" "'" ""} $name]
        set todaysPrograms [open ./rooms/${fileName}.htm w]
        fconfigure $todaysPrograms -encoding utf-8
        set templateFile [open ./generalTemplate.htm r]
        set template_data [read $templateFile]
        close $templateFile
        #Process data file
        set data [split $template_data "\n"]
        foreach line $data {
            regsub -all "!ROOMNAME!" $line [string  toupper $name] line
            regsub -all "!TIMESTAMP!" $line $currentUnixTime line
            puts $todaysPrograms $line
        }

        foreach id [dict get $bookings entries] {
            dict with id {
                set subTitle {}
                set shortDescription {}
                set privateEvent {}
                set status "published"
                set eventType {}
                set ages {}
                set modified {}
                set eventStart $startTime
                set eventEnd $endTime
                set endStamp [clock scan $endTime -format "%Y-%m-%d %H:%M:%S"]
                set start [clock format [clock scan $startTime -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                set end [clock format [clock scan $endTime -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                set room [dict get $locationMap $roomId]
                if {[string first "Rasmussen Room" $room] != -1 && [string first "Rasmussen" $name] != -1} {
                    set room $name
                }

                if {$name == $room && [expr {$endStamp - $currentStamp}] < 2592000 && [expr {$endStamp - $currentStamp}] > 0 && [string first "Discussion Room" $room] == -1 && ([string first "Central" $locationName] == 0 || [string first "Fountain" $locationName] == 0 )} {
                    if {[string is digit $eventId]} {
                        set status [getEventInfo $eventId "status" $accessToken]
                        if {$status == ""} {
                            set status "null"
                            puts "null event found with ID: $eventId"
                        } else {
                            set subTitle [getEventInfo $eventId "subTitle" $accessToken]
                            set privateEvent [getEventInfo $eventId "privateEvent" $accessToken]
                            set eventType [getEventInfo $eventId "types" $accessToken]
                            #set breakdownTime [getEventInfo $eventId "breakdownTime" $accessToken]
                            #set setupTime [getEventInfo $eventId "setupTime" $accessToken]
                            set eventEnd [getEventInfo $eventId "eventEnd" $accessToken]
                            set eventStart [getEventInfo $eventId "eventStart" $accessToken]
                            set ages [getEventInfo $eventId "ages" $accessToken]
                            set modified [getEventInfo $eventId "modified" $accessToken]
                            set start [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                            set end [clock format [clock scan $eventEnd -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                        }
                    }
                    if {[string first "Town Square"  $room] == 0} {
                        set shortDescription [getEventInfo $eventId "shortDescription" $accessToken]
                    }
                    if {$type == "Staff" || $privateEvent == "true"} {
                        set cat "private"
                    } elseif {$ages == "Teens"} {
                        set cat "teen"
                    } elseif {$ages == "Adults"} {
                        set cat "adult"
                    } elseif {$ages == "Kids"} {
                        set cat "kid"
                    } elseif {$ages == ""} {
                        set cat "booking"
                    } else  {
                        set cat ""
                    }
                    
                    if {$type == "Staff"} {
                        set displayName "Staff Meeting"
                    }
                    
                    if {$status != "published" || $modified == "rescheduled" || $modified == "canceled"} {
                        puts $todaysPrograms "<table class='event' style='display: none;'><tr><td/><td><div class='circle'>"
                    } else  {
                        puts $todaysPrograms "<table class='event' id='${endStamp}'><tr><td/><td><div class='circle ${cat}'>"
                    }
                    puts $todaysPrograms [string map {"  " " "} [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%a"]]
                    puts $todaysPrograms "<br><b>"
                    puts $todaysPrograms [string map {"  " " "} [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%e"]]
                    puts $todaysPrograms "</b><br>"
                    puts $todaysPrograms [string toupper [string map {"  " " "} [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%b"]]]
                    puts $todaysPrograms "</div></td><td><b>"
                    puts $todaysPrograms $displayName
                    if {[string length $subTitle] > 1} {
                        puts $todaysPrograms " - $subTitle"
                    }
                    puts $todaysPrograms "</b><br>"
                    puts $todaysPrograms [getEventTime $start $end]
                    puts $todaysPrograms "<br>"
                    puts $todaysPrograms [getLocation $locationName $room]
                    puts $todaysPrograms "</td><td/></tr></table>"
                    if {[string length $shortDescription] > 1} {
                        #puts $todaysPrograms "<br><small>[string toupper $shortDescription]</small>"
                    }
               }
            }
        }
                
        puts $todaysPrograms "<div id='end'></div><br></body></html>"
        close $todaysPrograms
    
    }
}

exit
