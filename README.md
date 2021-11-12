[![Actions Status](https://github.com/lizmat/IRC-Log/workflows/test/badge.svg)](https://github.com/lizmat/IRC-Log/actions)

NAME
====

IRC::Log - role providing interface to IRC logs

SYNOPSIS
========

```raku
use IRC::Log;

class IRC::Log::Foo does IRC::Log {
    method parse-log(
      str $text,
          $last-hour    is raw,
          $last-minute  is raw,
          $ordinal      is raw,
          $linenr       is raw,
    --> Nil) {
        ...
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

The `parse-log` method must be provided by the consuming class.

METHODS TO BE PROVIDED BY CONSUMER
==================================

parse-log
---------

```raku
    method parse-log(
      str $text,
          $last-hour   is raw,
          $last-minute is raw,
          $ordinal     is raw,
          $linenr      is raw,
    --> Nil) {
        ...
    }
```

The `parse-log` instance method should be provided by the consuming class. Examples of the implementation of this method can be found in the `IRC::Log::Colabti` and `IRC::Log::Textual` modules.

It is supposed to take 5 positional parameters that are assumed to be correctly updated by the logic in the `.parse-log` method.

  * the text to be parsed

The (partial) log to be parsed.

  * the last hour seen as a raw integer

An `is raw` variable that contains the last hour value seen in messages. It is set to -1 the first time, so that it is always unequal to any hour value that will be encountered.

  * the last minute seen as a raw integer

An `is raw` variable that contains the last minute value seen in messages. It is set to -1 the first time, so that it is always unequal to any minute value that will be encountered.

  * the last ordinal seen as a raw integer

An `is raw` variable that contains the last ordinal value seen in messages. It is set to 0 the first time.

  * the line number of the line last parsed

An `is raw` variable that contains the line number last parsed in the log. It is set to -1 the first time, so that the first line parsed will be 0.

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

date
----

```raku
say $log.date;
```

The `date` instance method returns the `Date` object for this log.

entries
-------

```raku
.say for $log.entries.List;                       # all entries

.say for $log.entries.List.grep(*.conversation);  # only actual conversation
```

The `entries` instance method returns an `IterationBuffer` with entries from the log. It contains instances of one of the following classes:

    IRC::Log::Joined
    IRC::Log::Left
    IRC::Log::Kick
    IRC::Log::Message
    IRC::Log::Mode
    IRC::Log::Nick-Change
    IRC::Log::Self-Reference
    IRC::Log::Topic

entries-ge-target
-----------------

```raku
.say for $log.entries-ge-target($target);
```

The `entries-from-target` instance method returns all entries that are `after` **and** including the given target.

entries-gt-target
-----------------

```raku
.say for $log.entries-gt-target($target);
```

The `entries-gt-target` instance method returns all entries that are `after` (so **not** including) the given target.

entries-le-target
-----------------

```raku
.say for $log.entries-le-target($target);
```

The `entries-le-target` instance method returns all entries that are `before` **and** including the given target.

entries-lt-target
-----------------

```raku
.say for $log.entries-lt-target($target);
```

The `entries-lt-target` instance method returns all entries that are `before` (so **not** including) the given target.

entries-of-nick
---------------

```raku
.say for $log.entries-of-nick($nick);
```

The `entries-of-nick` instance method takes a `nick` as parameter and returns a `Seq` consisting of the entries of the given nick (if any).

entries-of-nicks
----------------

```raku
.say for $log.entries-of-nicks(@nicks);
```

The `entries-of-nicks` instance method takes a list of `nicks` and returns a `Seq` consisting of the entries of the given nicks (if any).

first-entry
-----------

```raku
say $log.first-entry;
```

The `first-entry` instance method returns the first entry of the log.

first-target
------------

```raku
say $log.first-target;  # 2021-04-23
```

The `first-target` instance method returns the `target` of the first entry.

last-entry
----------

```raku
say $log.last-entry;
```

The `last-entry` instance method returns the last entry of the log.

last-target
-----------

```raku
say $log.last-target;  # 2021-04-29
```

The `last-target` instance method returns the `target` of the last entry.

last-topic-change
-----------------

```raku
say $log.last-topic-change;  # liz changed topic to "hello world"
```

The `last-topic-change` instance method returns the entry that contains the last change of topic. Returns `Nil` if there wasn't any topic change.

nick-names
----------

```raku
.say for $log.nick-names;
```

The `nick-names` instance method returns a native str array with the nick names that have been found in the order they were found.

nicks
-----

```raku
for $log.nicks -> (:key($nick), :value($entries)) {
    say "$nick has $entries.elems() entries";
}
```

The `nicks` instance method returns a `Map` with the nicks seen for this log as keys (in the order they were seen_, and an `IterationBuffer` with entries that originated by that nick.

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
.say for $log.problems.List;
```

The `problems` instance method returns an `IterationBuffer` with `Pair`s of lines that could **not** be interpreted in the log. The key is a string with the line number and a reason it could not be interpreted. The value is the actual line.

raw
---

```raku
say "contains 'foo'" if $log.raw.contains('foo');
```

The `raw` instance method returns the raw text version of the log. It can e.g. be used to do a quick check whether a string occurs in the raw text, before checking `entries` for a given string.

target-entry
------------

```raku
say "$target has $_" with $log.target-entry($target);
```

The `target-entry` returns the **entry** of the specified target, or it returns `Nil` if the entry of the target could not be found.

target-index
------------

```raku
say "$target at $_" with $log.target-index($target);
```

The `target-index` returns the **position** of the specified target in the list of `entries`, or it returns `Nil` if the target could not be found.

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

The `entries` of the `log` of this entry as an `IterationBuffer`.

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

### next

The next entry in this log (if any).

### nick

The nick of the user that originated the entry in the log.

### nick-index

The index of the nick in the list of `nick-names` in the log.

### ordinal

Zero-based ordinal number of this entry within the minute it occurred.

### pos

The position of this entry in the `entries` of the `log` of this entry.

### prefix

The prefix used in creating the `gist` of this entry.

### prev

The previous entry in this log (if any).

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

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/IRC-Log . Comments and Pull Requests are welcome.

COPYRIGHT AND LICENSE
=====================

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

