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
    set header [list Authorization "Basic ${auth}" User-Agent "DigitalSignageGen"]
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
    set header [list Authorization "Bearer ${accessToken}" User-Agent "DigitalSignageGen"]
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

proc getLocation {locationName roomName includeLocation} {
    if {[string first $includeLocation $locationName] != -1 } {
        set location $roomName
    } else  {
        set location $locationName
    }
    return $location
}

proc notEqualsList {lookfor list} {
    foreach val $list {
      if {$val == $lookfor} {
        return 0
      }
    }
    return 1
}

proc notContainsList {lookfor list} {
    foreach val $list {
      if {[string first $val $lookfor] != -1} {
        return 0
      }
    }
    return 1
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
set location [dict get $config location]
set average [dict get $config average]
set days [dict get $config days]
set start "0.[dict get $config start]"
set excludeRoom [split [dict get $config excludeRoom] ","]
set excludeTodaysRoom [split [dict get $config excludeTodaysRoom] ","]
set excludeTodaysType [split [dict get $config excludeTodaysType] ","]

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
            puts "Starting at reservationID $begin after $failed attempts at finding today's data"
            break
        }
        puts "Checking date of reservationID $startID"
        set startID [expr {$startID + $sweep}]
        incr failed
    }
}

set daysUnixTime [expr {$days * 60 * 60 * 24}]
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
set limit [expr {$days * ($average / 2)}]
set endDate [clock format [expr {$currentUnixTime + $daysUnixTime}] -format "%Y-%m-%d"]
set bookings [getAPIresult reserve/reservations?start=${begin}&limit=${limit}&status=approved&fields=eventId,locationName,type $accessToken]
set events [getAPIresult attend/events?start=0&limit=${limit}&status=published&startDate=${currentDate}&endDate=${endDate}&fields=shortDescription,privateEvent,types,setupTime,breakdownTime,status,ages,modified,registration $accessToken]

#Create page for all events happening today
set todaysDict {};
set todaysPrograms [open ./rooms/Combined.htm w]
fconfigure $todaysPrograms -encoding utf-8
set templateFile [open ./generalTemplate.htm r]
set template_data [read $templateFile]
close $templateFile
set data [split $template_data "\n"]
foreach line $data {
    regsub -all "!ROOMNAME!" $line "TODAY'S PROGRAMS" line
    regsub -all "!TIMESTAMP!" $line $currentUnixTime line
    puts $todaysPrograms $line
}

#Loop over every room and generate file for that room
set todaysCount 0
foreach habitation [dict get $rooms entries] {
    dict with habitation {
        set fileName [string map {" " "" "#" "" "/" "" "'" ""} $name]
        puts "Generating ${fileName}.htm"
        set thisRoomsPrograms [open ./rooms/${fileName}.htm w]
        fconfigure $thisRoomsPrograms -encoding utf-8

        foreach line $data {
            regsub -all "!ROOMNAME!" $line [string toupper $name] line
            regsub -all "!TIMESTAMP!" $line $currentUnixTime line
            puts $thisRoomsPrograms $line
        }

        foreach id [dict get $bookings entries] {
            dict with id {
                set subTitle {}
                set shortDescription {}
                set privateEvent {}
                set status {}
                set eventType {}
                set ages {}
                set modified {}
                set info {}
                set registration {}
                set eventStart $startTime
                set eventEnd $endTime
                set startStamp [clock scan $startTime -format "%Y-%m-%d %H:%M:%S"]
                set endStamp [clock scan $endTime -format "%Y-%m-%d %H:%M:%S"]
                set start [clock format [clock scan $startTime -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                set end [clock format [clock scan $endTime -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                set room [dict get $locationMap $roomId]
                if {[string first "Rasmussen Room" $room] != -1 && [string first "Rasmussen" $name] != -1} {
                    set room $name
                }

                if {$name == $room && [expr {$endStamp - $currentStamp}] < $daysUnixTime && [expr {$endStamp - $currentStamp}] > 0 && [notContainsList $room $excludeRoom] && [string first $location $locationName] == 0 } {
                    if {$type == "Event"} {
                        if {![string is digit $eventId]} {
                            puts "eventID is missing for reservation $reservationId!"
                        }
                        foreach event [dict get $events entries] {
                            if {$eventId == [dict get $event eventId] && [string is digit $eventId]} {
                                #puts "match found for $eventId"
                                set status [dict get $event status]
                                set subTitle [dict get $event subTitle]
                                set privateEvent [dict get $event privateEvent]
                                set eventType [dict get $event types]
                                set eventEnd  [dict get $event eventEnd]
                                set eventStart [dict get $event eventStart]
                                set ages [dict get $event ages]
                                set modified [dict get $event modified]
                                set registration [dict get $event registration]
                                set startStamp [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"]
                                set start [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                                set end [clock format [clock scan $eventEnd -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                            }
                        }
                    } else {
                        set status "published"
                    }

                    if {[string length $status] < 1 && $type == "Event"} {
                        puts "Null event found for $eventId!"
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
                        append info "<table class='event' style='display: none;'><tr><td/><td><div class='circle'>"
                    } else  {
                        append info "<table class='event' id='${endStamp}'><tr><td/><td><div class='circle ${cat}'>"
                    }
                    append info [string map {"  " " "} [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%a"]]
                    append info "<br><b>"
                    append info [string map {"  " " "} [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%e"]]
                    append info "</b><br>"
                    append info [string toupper [string map {"  " " "} [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%b"]]]
                    append info "</div></td><td><b>"
                    append info $displayName
                    if {[string length $subTitle] > 1} {
                        append info " - $subTitle"
                    }
                    append info "</b><br>"
                    append info [getEventTime $start $end]
                    append info "<br>"
                    append info [getLocation $locationName $room $location]
                    append info "</td><td/></tr></table>"
                    if {[string length $shortDescription] > 1} {
                        #puts $thisRoomsPrograms "<br><small>[string toupper $shortDescription]</small>"
                    }
                    puts $thisRoomsPrograms $info
                    if {[string first $currentDate $startTime] == 0 && [notEqualsList $type $excludeTodaysType] && [notContainsList $room $excludeTodaysRoom]} {
                        dict append todaysDict [expr {$startStamp + $todaysCount}] $info
                        incr todaysCount
                    }
               }
            }
        }
        puts $thisRoomsPrograms "<div id='end'></div><br></body></html>"
        close $thisRoomsPrograms
    }
}
set todaysSorted [lsort -integer -stride 2 $todaysDict]
foreach id [dict keys $todaysSorted] {
    puts $todaysPrograms [dict get $todaysSorted $id]
}
puts $todaysPrograms "<div id='end'></div><br></body></html>"
close $todaysPrograms

exit
