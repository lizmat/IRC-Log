[![Actions Status](https://github.com/lizmat/IRC-Log/workflows/test/badge.svg)](https://github.com/lizmat/IRC-Log/actions)

NAME
====

IRC::Log - role providing interface to IRC logs

SYNOPSIS
========

```raku
use IRC::Log;

class IRC::Log::Foo does IRC::Log {
    method parse($slurped, $date) {
        # Nil for already parsed and no change
        #   0 for initial parse
        # > 0 number of entries added after update
    }
}

my $log = IRC::Log::Foo.new($filename.IO);

say "Logs from $log.date()";
.say for $log.entries.List;

my $log = IRC::Log::Foo.new($text, $date);
```

DESCRIPTION
===========

IRC::Log provides a role providing an interface to IRC logs in various formats. Each log is supposed to contain all messages from a given date.

The `parse` method must be provided by the consuming class.

CLASS METHODS
=============

new
---

```raku
my $log = IRC::Log::Foo.new($filename.IO);

my $log = IRC::Log::Foo.new($text, $date);
```

The `new` class method either takes an `IO` object as the first parameter, and a `Date` object as the optional second parameter (eliding the `Date` from the basename if not specified), and returns an instantiated object representing the entries in that log file.

Or it will take a `Str` as the first parameter for the text of the log, and a `Date` as the second parameter.

Any lines that can not be interpreted, are ignored: they are available with the `problems` method.

IO2Date
-------

```raku
with IRC::Log::Foo.IO2Date($path) -> $date {
    say "the date of $path is $date";
}
else {
    say "$path does not appear to be a log file";
}
```

The `IO2Date` class method interpretes the given `IO::Path` object and attempts to elide a `Date` object from it. It returns `Nil` if it could not.

INSTANCE METHODS
================

entries
-------

```raku
.say for $log.entries.List;                      # all entries

.say for $log.entries.Seq.grep(*.conversation);  # only actual conversation
```

The `entries` instance method returns an IterationBuffer with entries from the log. It contains instances of one of the following classes:

    IRC::Log::Joined
    IRC::Log::Left
    IRC::Log::Kick
    IRC::Log::Message
    IRC::Log::Mode
    IRC::Log::Nick-Change
    IRC::Log::Self-Reference
    IRC::Log::Topic

date
----

```raku
say $log.date;
```

The `date` instance method returns the `Date` object for this log.

first-target
------------

```raku
say $first-target;  # 2021-04-23
```

The `first-target` instance method returns the `target` of the first entry.

last-target
-----------

```raku
say $last-target;  # 2021-04-29
```

The `last-target` instance method returns the `target` of the last entry.

nicks
-----

```raku
for $log.nicks.sort(*.key) -> (:key($nick), :value($entries)) {
    say "$nick has $entries.elems() entries";
}
```

The `nicks` instance method returns a `Map` with the nicks seen for this log as keys, and an `IterationBuffer` with entries that originated by that nick.

nr-control-entries
------------------

```raku
say $log.nr-control-entries;
```

The `nr-control-entries` instance method returns an integer representing the number of control entries in this log. It is calculated lazily

nr-conversation-entries
-----------------------

```raku
say $log.nr-conversation-entries;
```

The `nr-conversation-entries` instance method returns an integer representing the number of conversation entries in this log.

problems
--------

```raku
.say for $log.problems;
```

The `problems` instance method returns an array with `Pair`s of lines that could not be interpreted in the log. The key is a string with the line number and a reason it could not be interpreted. The value is the actual line.

raw
---

```raku
say "contains 'foo'" if $log.raw.contains('foo');
```

The `raw` instance method returns the raw text version of the log. It can e.g. be used to do a quick check whether a string occurs in the raw text, before checking `entries` for a given string.

update
------

```raku
$log.update($filename.IO);  # add any entries added to file

$log.update($slurped);      # add any entries added to string
```

The `update` instance method allows updating a log with any additional entries. This is primarily intended to allow for updating a log on the current date, as logs of previous dates should probably be deemed immutable.

CLASSES
=======

All of the classes that are returned by the `entries` methods, have the following methods in common:

### control

Returns `True` if this entry is a control message. Else, it returns `False`.

These entry types are considered control messages:

    IRC::Log::Joined
    IRC::Log::Left
    IRC::Log::Kick
    IRC::Log::Mode
    IRC::Log::Nick-Change
    IRC::Log::Topic

### conversation

Returns `True` if this entry is part of a conversation. Else, it returns `False`.

These entry types are considered conversational messages:

    IRC::Log::Message
    IRC::Log::Self-Reference
    IRC::Log::Topic

### date

The `Date` of this entry.

### entries

The `entries` of the `log` of this entry.

### gist

Create the string representation of the entry as it originally occurred in the log.

### hhmm

A string representation of the hour and the minute of this entry ("hhmm").

### hh-mm

A string representation of the hour and the minute of this entry ("hh:mm").

### hour

The hour (in UTC) the entry was added to the log.

### log

The `IRC::Log` object of which this entry is a part.

### message

The text representation of the entry.

### minute

The minute (in UTC) the entry was added to the log.

### nick

The nick of the user that originated the entry in the log.

### ordinal

Zero-based ordinal number of this entry within the minute it occurred.

### pos

The position of this entry in the `entries` of the `log` of this entry.

### prefix

The prefix used in creating the `gist` of this entry.

### problems

The `problems` of the `log` of this entry.

### sender

A representation of the sender. The same as `nick` for the `Message` class, otherwise the empty string as then the nick is encoded in the `message`.

### target

Representation of an anchor in an HTML-file for deep linking to this entry. Can also be used as a sort key across entries from multiple dates.

IRC::Log::Joined
----------------

No other methods are provided.

IRC::Log::Left
--------------

No other methods are provided.

IRC::Log::Kick
--------------

### kickee

The nick of the user that was kicked in this log entry.

### spec

The specification with which the user was kicked in this log entry.

IRC::Log::Message
-----------------

### text

The text that the user entered that resulted in this log entry.

IRC::Log::Mode
--------------

### flags

The flags that the user entered that resulted in this log entry.

### nicks

An array of nicknames (to which the flag setting should be applied) that the user entered that resulted in this log entry.

IRC::Log::Nick-Change
---------------------

### new-nick

The new nick of the user that resulted in this log entry.

IRC::Log::Self-Reference
------------------------

### text

The text that the user entered that resulted in this log entry.

IRC::Log::Topic
---------------

### text

The new topic that the user entered that resulted in this log entry.

AUTHOR
======

Elizabeth Mattijsen <liz@wenzperl.nl>

Source can be located at: https://github.com/lizmat/IRC-Log . Comments and Pull Requests are welcome.

COPYRIGHT AND LICENSE
=====================

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

