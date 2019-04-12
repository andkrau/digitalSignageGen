digitalSignageGen
========

This program creates digital signage for Communico events and bookings.
It can be considered a static site generator for each of the rooms at the library.
There is also a "Today's Events" page that gives an overview of everything that is happening that day.

## Usage

```html
Windows:
tclsh86.exe C:\somePath\digitalSignageGen.tcl
or
digitalSignageGen.exe

Unix:
tclsh \somePath\digitalSignageGen.tcl
```

The config file requires the following options:

    key
    Communico API key goes here.

    secret
    Communico API secret goes here.

    average
    The average number of bookings/events per day.

    start
    What percent of the total number of bookings/events to skip when starting the search for today's data.
    This setting shouldn't need to be changed.

    days
    How many days of events to show at once.

    location
    Library location name as configured in Communico.

    includeSubtitle
    Enabling this will add the subtitle to the title of the event.

    roomWhitelist
    These rooms will have HTML pages created for them.
    This list should be comma separated and contain no spaces.

    roomBlacklist
    These rooms will never have HTML pages created for them.
    This list should be comma separated and contain no spaces.

    todaysWhitelist
    Which rooms to include in "today's events" feed. This list should be a subset of "roomWhitelist".
    This list should be comma separated and contain no spaces.

    todaysBlacklist
    Which rooms to never include in "today's events" feed.
    This list should be comma separated and contain no spaces.

    roomStaffWhitelist
    These rooms will include "Staff" booking types in their pages.
    This list should be comma separated and contain no spaces.

    roomStaffBlacklist
    These rooms will never include "Staff" booking types in their pages.
    This list should be comma separated and contain no spaces.

    hideStaffDisplayName
    Whether to hide the "real" booking title for staff bookings.

    excludeTodaysType
    Used to hide bookings by type from the "today's events" feed.
    This list should be comma separated and contain no spaces.

    dash
    Which character to use as a dash for times. ndash should be "&ndash;". mdash should be "&mdash;".
    Use of "-" will automatically be padded with spaces. To turn this off, use "&#8208;".

    noon
    How to format "12:00 pm". "noon" or "Noon" are suggested.

    buttonsRoom
    Disabling this will remove the overlay buttons for rooms.

    buttonsTodays
    Disabling this will remove the overlay buttons for "today's events".

    refresh
    Refresh interval for the pages in minutes.

    maxEvents
    Maximum number of events to display.

    filterStrings
    Words or phrases to remove from room names.
    The option should be surrounded by curly braces (to allow for spaces) and comma separated.

    dateOrder
    Which order to have the date elements inside of the date circle.
    Valid options are dayOfWeek, dayOfMonth, and month; comma separated.
    Any combination of these values is acceptable as long as at least one value is supplied.

    scaleRoom
    The minimum number of visible events before enabling content scaling.
    Setting this value greater than 0 will fit up to 12 items on the room displays.
    This is best used whith buttonsRoom disabled and maxEvents set to under 12.

    scaleTodays
    The minimum number of visible events before enabling content scaling.
    Setting this value greater than 0 fit up to 12 items on the "today's events" display.
    This is best used whith buttonsTodays disabled.

    registrationDetails
    Whether to show if the event is registered or drop-in.

    todaysFile
    The base file name for the "today's events" display.

    todaysTitle
    The title for the "today's events" display.
    If spaces are used, surround with curly braces.

    combinedRoom
    Rooms to be treated as parent and child.
    First value should be parent room and second should be a substring common among the children.
    Values should be comma separated. If spaces are used, surround with curly brace.