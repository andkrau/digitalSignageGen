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

proc getAPIkey {} {
    set offset 1
    set base "https://api.communico.co/v3"
    set clientKey "KEY-GOES-HERE"
    set secretKey "SECRET-GOES-HERE"
    set authKey [::base64::encode -maxlen 0 ${clientKey}:${secretKey}]
    set header [list Authorization "Basic ${authKey}"]
    set token [::http::geturl ${base}/token -headers $header -query "grant_type=client_credentials"]
    set response [::http::data $token]
    set response [split $response {\"}]
    set accessType [lindex $response 9]
    set accessKey [lindex $response 3]
    puts "Key Received: $accessType $accessKey"
    return $accessKey
}

proc getAPIresult {URL accessKey} {
    set base "https://api.communico.co/v3"
    set header [list Authorization "Bearer ${accessKey}" User-Agent "LibraryTEST"]
    set token [::http::geturl ${base}/${URL} -headers $header -method GET]
    set response [::http::data $token]
    set json [::json::json2dict $response]
    set result [dict get $json data]
    return $result
}

proc getEventInfo {eventId lookupValue accessKey} {
    set matchingEvent [getAPIresult attend/events/${eventId}?fields=shortDescription,privateEvent,types,setupTime,breakdownTime,status,ages,modified $accessKey]
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
    if {[string first Central $locationName] != -1 } {
        set location $roomName
    } else  {
        set location $locationName
    }
    return $location
}

set accessKey [getAPIkey]

#There is no way to pick specific dates or date ranges when looking up room bookings
#Since we require patron bookings to be included, we must somehow find the days we are looking for
#This will sweep over all bookings, starting at booking number 25000, to find today's bookings
#The sweep is fairly fast due to going quickly until we get closer to today's bookings
#the sweep method is based upon the average number of bookings per day and may need to be adjusted
set startID 10000
set failed 0
set sweep 800
while {$failed < 100} {
    set startSearch [getAPIresult reserve/reservations?start=${startID}&limit=1 $accessKey]
    foreach id [dict get $startSearch entries] {
        dict with id {
            set recordUnixTime [clock scan $startTime -format "%Y-%m-%d %H:%M:%S"]
            
        }
    }
    if {[dict exists $startSearch entries]} {
        set currentUnixTime [clock seconds]
        if {($currentUnixTime - $recordUnixTime) < 5184000} {
            set sweep 400
        }
        if {($currentUnixTime - $recordUnixTime) < 2592000} {
            set sweep 100
        }
        if {($currentUnixTime - $recordUnixTime) < 1209600} {
            set sweep 50
        }
        if {($currentUnixTime - $recordUnixTime) < 604800} {
            set begin [expr {$startID + 0}]
            puts "Starting at $begin"
            break
        }
        puts "sweep is on $startID"
        set startID [expr {$startID + $sweep}]
        incr failed
    }
}

set prettyDate [string toupper [clock format [clock seconds] -format "%A, %B %d"]]
set currentDate [clock format [clock seconds] -format "%Y-%m-%d"]
set currentStamp [clock seconds]
set rooms [getAPIresult reserve/rooms $accessKey]
set locationMap [dict create]
foreach item [dict get $rooms entries] {
    dict with item {
        dict set locationMap $roomId $name
    }
}
set bookings [getAPIresult reserve/reservations?start=${begin}&limit=700&status=approved&fields=eventId,locationName,type $accessKey]
set events [getAPIresult attend/events?start=0&limit=5&privateEvents=false&status=published&startDate=${currentDate}&endDate=${currentDate}&types=Bus%20Trips $accessKey]

#Loop over every room and generate file for that room
foreach habitation [dict get $rooms entries] {
    dict with habitation {
        set fileName [string map {" " "" "#" "" "/" ""} $name]
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
                if {$name == $room && [expr {$endStamp - $currentStamp}] < 2592000 && [expr {$endStamp - $currentStamp}] > 0 && [string first "Discussion Room" $room] == -1 && [string first "Central" $locationName] == 0} {
                    if {[string is digit $eventId]} {
                        set status [getEventInfo $eventId "status" $accessKey]
                        if {$status == ""} {
                            set status "null"
                            puts "null event found with ID: $eventId"
                        } else {
                            set subTitle [getEventInfo $eventId "subTitle" $accessKey]
                            set privateEvent [getEventInfo $eventId "privateEvent" $accessKey]
                            set eventType [getEventInfo $eventId "types" $accessKey]
                            #set breakdownTime [getEventInfo $eventId "breakdownTime" $accessKey]
                            #set setupTime [getEventInfo $eventId "setupTime" $accessKey]
                            set eventEnd [getEventInfo $eventId "eventEnd" $accessKey]
                            set eventStart [getEventInfo $eventId "eventStart" $accessKey]
                            set ages [getEventInfo $eventId "ages" $accessKey]
                            set modified [getEventInfo $eventId "modified" $accessKey]
                            set start [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                            set end [clock format [clock scan $eventEnd -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                        }
                    }
                    if {[string first "Town Square"  $room] == 0} {
                        set shortDescription [getEventInfo $eventId "shortDescription" $accessKey]
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