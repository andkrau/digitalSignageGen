#   Creates digital signage for Communico events and bookings

#   https://github.com/andkrau/digitalSignageGen

#   Copyright (C) 2017-2021 Andrew Krause <akrause@stdl.org>

#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as
#   published by the Free Software Foundation, either version 3 of the
#   License, or (at your option) any later version.

#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.

#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

package require sha256
package require base64
package require http
package require json

encoding system utf-8

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
    set ::http::defaultCharset utf-8
    set token [::http::geturl ${base}/${URL} -headers $header -method GET]
    set response [::http::data $token]
    set json [::json::json2dict $response]
    set result [encoding convertfrom utf-8 [dict get $json data]]
    return $result
}

proc getEventTime {start end dash noon} {
    set start [string map [list "12:00 pm" $noon] $start]
    set end [string map  [list "12:00 pm" $noon] $end]
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
    set times "${start}${dash}${end}"
    set times [string map {"am-" "am - "} $times]
    set times [string map {"am" "a.m."} $times]
    set times [string map {"pm" "p.m."} $times]
    set times [string map {":00" ""} $times]
    return $times
}

proc stripList {original filterStrings} {
    foreach val $filterStrings {
        set original [string map [list $val ""] $original]
    }
    return $original
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

proc booleanContainsList {lookfor list whitelist} {
    set found 0
    foreach val $list {
      if {[string first $val $lookfor] != -1} {
        set found 1
      }
    }
    if {$found == 0 && $whitelist} {
        return 0
    } elseif {$found == 1 && $whitelist} {
        return 1
    } elseif {$found == 1} {
        return 0
    } else {
        return 1
    }
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

if {   ![dict exist $config key] || ![dict exist $config secret]
    || ![dict exist $config limit]
    || ![dict exist $config days] || ![dict exist $config location]
    || ![dict exist $config includeSubtitle] || ![dict exist $config roomWhitelist]
    || ![dict exist $config roomBlacklist] || ![dict exist $config todaysWhitelist]
    || ![dict exist $config todaysBlacklist] || ![dict exist $config roomStaffWhitelist]
    || ![dict exist $config roomStaffWhitelist] || ![dict exist $config roomStaffBlacklist]
    || ![dict exist $config hideStaffDisplayName] || ![dict exist $config excludeTodaysType]
    || ![dict exist $config dash] || ![dict exist $config noon]
    || ![dict exist $config buttonRoom] || ![dict exist $config buttonTodays]
    || ![dict exist $config filterStrings] || ![dict exist $config dateOrder]
    || ![dict exist $config scaleRoom] || ![dict exist $config scaleTodays]
    || ![dict exist $config refresh] || ![dict exist $config maxEvents]
    || ![dict exist $config registrationDetails] || ![dict exist $config todaysFile]
    || ![dict exist $config todaysTitle] || ![dict exist $config combinedRoom] } {
    puts "Required config option(s) missing!"
    exit
}

set key [dict get $config key]
set secret [dict get $config secret]
set location [dict get $config location]
set limit [dict get $config limit]
set days [dict get $config days]
set dash [dict get $config dash]
set noon [dict get $config noon]
set refresh [dict get $config refresh]
set maxEvents [dict get $config maxEvents]
set buttonRoom [dict get $config buttonRoom]
set registrationDetails [dict get $config registrationDetails]
set buttonTodays [dict get $config buttonTodays]
set scaleRoom [dict get $config scaleRoom]
set scaleTodays [dict get $config scaleTodays]
set todaysFile [dict get $config todaysFile]
set todaysTitle [dict get $config todaysTitle]
set includeSubtitle [dict get $config includeSubtitle]
set hideStaffDisplayName [dict get $config hideStaffDisplayName]
set roomWhitelist [split [dict get $config roomWhitelist] ","]
set roomBlacklist [split [dict get $config roomBlacklist] ","]
set roomStaffWhitelist [split [dict get $config roomStaffWhitelist] ","]
set roomStaffBlacklist [split [dict get $config roomStaffBlacklist] ","]
set todaysWhitelist [split [dict get $config roomWhitelist] ","]
set todaysBlacklist [split [dict get $config todaysBlacklist] ","]
set excludeTodaysType [split [dict get $config excludeTodaysType] ","]
set filterStrings [split [dict get $config filterStrings] ","]
set dateOrder [split [dict get $config dateOrder] ","]
set combinedRoom [split [dict get $config combinedRoom] ","]

if {$registrationDetails == "no"} {
    set registrationDetails "none"
} else {
    set registrationDetails "inline"
}

if {$buttonTodays == "no"} {
    set buttonTodays "none"
} else {
    set buttonTodays "inline"
}

if {$buttonRoom == "no"} {
    set buttonRoom "none"
} else {
    set buttonRoom "inline"
}

set accessToken [getAPItoken $key $secret]
set currentUnixTime [clock seconds]
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
set endDate [clock format [expr {$currentUnixTime + $daysUnixTime}] -format "%Y-%m-%d"]
set bookings [getAPIresult reserve/reservations?start=0&limit=${limit}&status=approved&startDate=${currentDate}&endDate=${endDate}&fields=eventId,locationName,type $accessToken]
set events [getAPIresult attend/events?start=0&limit=${limit}&status=published&startDate=${currentDate}&endDate=${endDate}&fields=shortDescription,privateEvent,types,setupTime,breakdownTime,status,ages,modified,registration $accessToken]

#Create page for all events happening today
set todaysDict {};
set todaysPrograms [open ./rooms/${todaysFile}.htm w]
fconfigure $todaysPrograms -encoding utf-8
set templateFile [open ./generalTemplate.htm r]
set template_data [read $templateFile]
close $templateFile
set data [split $template_data "\n"]
foreach line $data {
    regsub -all "!ROOMNAME!" $line $todaysTitle line
    regsub -all "!TODAYSTITLE!" $line $todaysTitle line
    regsub -all "!TIMESTAMP!" $line $currentUnixTime line
    regsub -all "!REFRESH!" $line [expr {$refresh * 60000}] line
    regsub -all "!MAXEVENTS!" $line $maxEvents line
    regsub -all "!BUTTON!" $line $buttonTodays line
    regsub -all "!SCALE!" $line $scaleTodays line
    regsub -all "!REGISTRATION!" $line $registrationDetails line
    regsub -all "!LOCATION!" $line "inline" line
    puts $todaysPrograms $line
}

#Loop over every room and generate file for that room
set todaysCount 0
foreach habitation [dict get $rooms entries] {
    dict with habitation {
        if {[booleanContainsList $name $roomWhitelist 1] && [booleanContainsList $name $roomBlacklist 0]} {
            set fileName [string map {" " "" "#" "" "/" "" "'" ""} $name]
            puts "Generating ${fileName}.htm"
            set thisRoomsPrograms [open ./rooms/${fileName}.htm w]
            fconfigure $thisRoomsPrograms -encoding utf-8
            set roomRenamed [stripList [string toupper $name] $filterStrings]
            foreach line $data {
                regsub -all "!ROOMNAME!" $line $roomRenamed line
                regsub -all "!TODAYSTITLE!" $line $todaysTitle line
                regsub -all "!TIMESTAMP!" $line $currentUnixTime line
                regsub -all "!REFRESH!" $line [expr {$refresh * 60000}] line
                regsub -all "!MAXEVENTS!" $line $maxEvents line
                regsub -all "!BUTTON!" $line $buttonRoom line
                regsub -all "!SCALE!" $line $scaleRoom line
                regsub -all "!REGISTRATION!" $line $registrationDetails line
                regsub -all "!LOCATION!" $line "none" line
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
                    set notChild 1
                    set eventStart $startTime
                    set eventEnd $endTime
                    set startStamp [clock scan $startTime -format "%Y-%m-%d %H:%M:%S"]
                    set endStamp [clock scan $endTime -format "%Y-%m-%d %H:%M:%S"]
                    set start [clock format [clock scan $startTime -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                    set end [clock format [clock scan $endTime -format "%Y-%m-%d %H:%M:%S"] -format "%l:%M %P"]
                    set room [dict get $locationMap $roomId]
                    if {[string first [lindex $combinedRoom 0] $room] != -1 && [string first [lindex $combinedRoom 1] $name] != -1} {
                        if {$room != $name} {
                            set notChild 0
                        }
                        set room $name
                    }

                    if {$name == $room && [expr {$endStamp - $currentStamp}] < $daysUnixTime && [expr {$endStamp - $currentStamp}] > 0 && [string first $location $locationName] == 0 } {
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
                                    set endStamp [clock scan $eventEnd -format "%Y-%m-%d %H:%M:%S"]
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

                        if {$type == "Staff" && $hideStaffDisplayName == "yes"} {
                            set displayName "Staff Meeting"
                        }

                        if {$status != "published" || $modified == "rescheduled" || $modified == "canceled" || $privateEvent == "true"} {
                            append info "<table class='event' id='0'><tr><td/><td><div class='circle'>"
                        } else  {
                            append info "<table class='event' id='${endStamp}'><tr><td/><td><div class='circle ${cat}'>"
                        }
                        set dayOfWeek [string map {"  " " "} [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%a"]]
                        set dayOfMonth [string map {"  " " "} [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%e"]]
                        set month [string toupper [string map {"  " " "} [clock format [clock scan $eventStart -format "%Y-%m-%d %H:%M:%S"] -format "%b"]]]

                        foreach val $dateOrder {
                            set double [subst $$val]
                            append info "<span class='${val}'>${double}</span><br>"
                        }

                        append info "</div></td><td><b>"
                        append info $displayName
                        if {$includeSubtitle == "yes" && [string length $subTitle] > 1} {
                            append info " - $subTitle"
                        }
                        append info "</b><br>"
                        append info [getEventTime $start $end $dash $noon]
                        append info "<span class='location'><br>"
                        append info [getLocation $locationName $room $location]
                        append info "</span>"
                        append info "<br>"
                        if {$type == "Event"} {
                          append info "<span class='registration'>"
                          if {$registration == "true"} {
                                append info "Library event. Registration required."
                          } else {
                                append info "Library event. Drop in."
                          }
                          append info "</span>"
                        }
                        append info "</td><td/></tr></table>"

                        if {$type == "Staff" && [booleanContainsList $room $roomStaffWhitelist 1] && [booleanContainsList $room $roomStaffBlacklist 0]} {
                            puts $thisRoomsPrograms $info
                        } elseif {$type != "Staff"} {
                            puts $thisRoomsPrograms $info
                        }

                        if {[notEqualsList $type $excludeTodaysType] && [booleanContainsList $room $todaysWhitelist 1] && [booleanContainsList $room $todaysBlacklist 0] && $notChild} {
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
}
set todaysSorted [lsort -integer -stride 2 $todaysDict]
foreach id [dict keys $todaysSorted] {
    puts $todaysPrograms [dict get $todaysSorted $id]
}
puts $todaysPrograms "<div id='end'></div><br></body></html>"
close $todaysPrograms

exit
