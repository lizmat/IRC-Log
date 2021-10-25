use v6.*;

role IRC::Log:ver<0.0.13>:auth<zef:lizmat> {
    has Date $.date;
    has Str  $.raw;
    has      $.entries;
    has Int  $.nr-control-entries;
    has Int  $.nr-conversation-entries;
    has      $.last-topic-change;
    has      @.problems;
    has      %.nicks;
    has      %!state;  # hash with final state of internal parsing

#-------------------------------------------------------------------------------
# Main log parser logic

    method !INIT() {
        $!entries := IterationBuffer.CREATE;
        self
    }

    method parse(::?CLASS:D: Str:D $slurped, Date:D $date) is implementation-detail {
        ...
    }

#-------------------------------------------------------------------------------
# Class methods

    method IO2Date(::?CLASS:U: IO:D $path) {
        try $path.basename.split(".").head.Date
    }

    proto method new(|) {*}
    multi method new(::?CLASS:U:
      IO:D $path,
      Date() $date = self.IO2Date($path)
    ) {
        my $instance := self.CREATE!INIT;
        $instance.parse($path.slurp(:enc("utf8-c8")), $date);
        $instance
    }

    multi method new(::?CLASS:U:
      Str:D $slurped,
      Date() $date
    ) {
        my $instance := self.CREATE!INIT;
        $instance.parse($slurped, $date);
        $instance
    }

#-------------------------------------------------------------------------------
# Instance methods

    method first-entry(::?CLASS:D:) { $!entries[0] }
    method last-entry( ::?CLASS:D:) { $!entries[$!entries.elems - 1] }

    method first-target(::?CLASS:D:) { $!entries[0].target }
    method last-target( ::?CLASS:D:) { $!entries[$!entries.elems - 1].target }

    method this-target(::?CLASS:D: Str:D $target) {
        $!entries.List.first($target eq *.target)
    }

    multi method update(::?CLASS:D: IO:D $path) {
        self.parse($path.slurp(:enc("utf8-c8")), $!date)
    }
    multi method update(::?CLASS:D: Str:D $slurped) {
        self.parse($slurped, $!date)
    }
}

#-------------------------------------------------------------------------------
# Expected messsage types

role IRC::Log::Entry {
    has     $.log is built(:bind);
    has int $!hmop;
    has str $.nick;

    method TWEAK(
      uint8 :$hour, uint8 :$minute, uint16 :$ordinal, uint32 :$pos
    ) {
        $!hmop = ($hour +< 56) + ($minute +< 48) + ($ordinal +< 32) + $pos;
    }

    method target() {
        my int $hour    = $.hour;
        my int $minute  = $.minute;
        my int $ordinal = $.ordinal;

        my $target = self.date
          ~ 'Z'
          ~ ($hour < 10 ?? "0$hour" !! $hour)
          ~ ':'
          ~ ($minute < 10 ?? "0$minute" !! $minute);

        $target = $target ~ '-' ~ ($ordinal < 10
          ?? "000$ordinal"
          !! $ordinal < 100
            ?? "00$ordinal"
            !! $ordinal < 1000
              ?? "0$ordinal"
              !! $ordinal
        ) if $ordinal;
        $target
    }

    method hour()     { $!hmop +> 56 +&   0xff }
    method minute()   { $!hmop +> 48 +&   0xff }
    method ordinal()  { $!hmop +> 32 +& 0xffff }
    method pos()      { $!hmop       +& 0xffff }
    method date()     { $!log.date         }
    method entries()  { $!log.entries.List }
    method problems() { $!log.problems     }

    method prev() {
        (my int $pos = self.pos) ?? $!log.entries[$pos - 1] !! Nil
    }
    method next() {
        $!log.entries[self.pos + 1] // Nil
    }

    method prefix(--> '*** ') { }
    method gist() {
        '[' ~ self.hh-mm ~ '] ' ~ self.prefix ~ self.message
    }

    method sender(--> '') { }
    method control(      --> True) { }
    method conversation(--> False) { }

    method hhmm() { 
        my int $hour   = $.hour;
        my int $minute = $.minute;
        ($hour < 10 ?? "0$hour" !! $hour)
          ~ ($minute < 10 ?? "0$minute" !! $minute)
    }
    method hh-mm() { 
        my int $hour   = $.hour;
        my int $minute = $.minute;
        ($hour < 10 ?? "0$hour" !! $hour)
          ~ ":"
          ~ ($minute < 10 ?? "0$minute" !! $minute)
    }
}

class IRC::Log::Joined does IRC::Log::Entry {
    method message() { "$!nick joined" }
}
class IRC::Log::Left does IRC::Log::Entry {
    method message() { "$!nick left" }
}
class IRC::Log::Kick does IRC::Log::Entry {
    has Str $.kickee is built(:bind);
    has Str $.spec   is built(:bind);

    method message() { "$!kickee was kicked by $!nick $!spec" }
}
class IRC::Log::Message does IRC::Log::Entry {
    has Str $.text is built(:bind);

    method gist() { '[' ~ self.hh-mm ~ '] <' ~ $.nick ~ '> ' ~ $.message }
    method sender() { $!nick }
    method message() { $!text }
    method prefix(--> '') { }
    method control(    --> False) { }
    method conversation(--> True) { }
}
class IRC::Log::Mode does IRC::Log::Entry {
    has Str $.flags is built(:bind);
    has Str @.nicks is built(:bind);

    method message() { "$!nick sets mode: $!flags @.nicks.join(" ")" }
}
class IRC::Log::Nick-Change does IRC::Log::Entry {
    has Str $.new-nick is built(:bind);

    method message() { "$!nick is now known as $!new-nick" }
}
class IRC::Log::Self-Reference does IRC::Log::Entry {
    has Str $.text is built(:bind);

    method prefix(--> '* ') { }
    method message() { "$!nick $!text" }
    method control(    --> False) { }
    method conversation(--> True) { }
}
class IRC::Log::Topic does IRC::Log::Entry {
    has Str $.text is built(:bind);

    method message() { "$!nick changes topic to: $!text" }
    method conversation(--> True) { }
}

#-------------------------------------------------------------------------------
# Documentation

=begin pod

=head1 NAME

IRC::Log - role providing interface to IRC logs

=head1 SYNOPSIS

=begin code :lang<raku>

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

=end code

=head1 DESCRIPTION

IRC::Log provides a role providing an interface to IRC logs in various
formats.  Each log is supposed to contain all messages from a given
date.

The C<parse> method must be provided by the consuming class.

=head1 CLASS METHODS

=head2 new

=begin code :lang<raku>

my $log = IRC::Log::Foo.new($filename.IO);

my $log = IRC::Log::Foo.new($text, $date);

=end code

The C<new> class method either takes an C<IO> object as the first parameter,
and a C<Date> object as the optional second parameter (eliding the C<Date>
from the basename if not specified), and returns an instantiated object
representing the entries in that log file.

Or it will take a C<Str> as the first parameter for the text of the log,
and a C<Date> as the second parameter.

Any lines that can not be interpreted, are ignored: they are available
with the C<problems> method.

=head2 IO2Date

=begin code :lang<raku>

with IRC::Log::Foo.IO2Date($path) -> $date {
    say "the date of $path is $date";
}
else {
    say "$path does not appear to be a log file";
}

=end code

The C<IO2Date> class method interpretes the given C<IO::Path> object
and attempts to elide a C<Date> object from it.  It returns C<Nil> if
it could not.

=head1 INSTANCE METHODS

=head2 entries

=begin code :lang<raku>

.say for $log.entries.List;                      # all entries

.say for $log.entries.Seq.grep(*.conversation);  # only actual conversation

=end code

The C<entries> instance method returns an IterationBuffer with entries from
the log.  It contains instances of one of the following classes:

    IRC::Log::Joined
    IRC::Log::Left
    IRC::Log::Kick
    IRC::Log::Message
    IRC::Log::Mode
    IRC::Log::Nick-Change
    IRC::Log::Self-Reference
    IRC::Log::Topic

=head2 date

=begin code :lang<raku>

say $log.date;

=end code

The C<date> instance method returns the C<Date> object for this log.

=head2 first-entry

=begin code :lang<raku>

say $log.first-entry;

=end code

The C<first-entry> instance method returns the first entry of the log.

=head2 first-target

=begin code :lang<raku>

say $log.first-target;  # 2021-04-23

=end code

The C<first-target> instance method returns the C<target> of the first entry.

=head2 last-entry

=begin code :lang<raku>

say $log.last-entry;

=end code

The C<last-entry> instance method returns the last entry of the log.

=head2 last-target

=begin code :lang<raku>

say $log.last-target;  # 2021-04-29

=end code

The C<last-target> instance method returns the C<target> of the last entry.

=head2 last-topic-change

=begin code :lang<raku>

say $log.last-topic-change;  # liz changed topic to "hello world"

=end code

The C<last-topic-change> instance method returns the entry that contains the
last change of topic.  Returns C<Nil> if there wasn't any topic change.

=head2 nicks

=begin code :lang<raku>

for $log.nicks.sort(*.key) -> (:key($nick), :value($entries)) {
    say "$nick has $entries.elems() entries";
}

=end code

The C<nicks> instance method returns a C<Map> with the nicks seen
for this log as keys, and an C<IterationBuffer> with entries that originated
by that nick.

=head2 nr-control-entries

=begin code :lang<raku>

say $log.nr-control-entries;

=end code

The C<nr-control-entries> instance method returns an integer representing
the number of control entries in this log.  It is calculated lazily

=head2 nr-conversation-entries

=begin code :lang<raku>

say $log.nr-conversation-entries;

=end code

The C<nr-conversation-entries> instance method returns an integer representing
the number of conversation entries in this log.

=head2 problems

=begin code :lang<raku>

.say for $log.problems;

=end code

The C<problems> instance method returns an array with C<Pair>s of
lines that could not be interpreted in the log.  The key is a string
with the line number and a reason it could not be interpreted.  The
value is the actual line.

=head2 raw

=begin code :lang<raku>

say "contains 'foo'" if $log.raw.contains('foo');

=end code

The C<raw> instance method returns the raw text version of the log.  It can
e.g. be used to do a quick check whether a string occurs in the raw text,
before checking C<entries> for a given string.

=head2 update

=begin code :lang<raku>

$log.update($filename.IO);  # add any entries added to file

$log.update($slurped);      # add any entries added to string

=end code

The C<update> instance method allows updating a log with any additional
entries.  This is primarily intended to allow for updating a log on the
current date, as logs of previous dates should probably be deemed immutable.

=head1 CLASSES

All of the classes that are returned by the C<entries> methods, have
the following methods in common:

=head3 control

Returns C<True> if this entry is a control message.  Else, it returns C<False>.

These entry types are considered control messages:

    IRC::Log::Joined
    IRC::Log::Left
    IRC::Log::Kick
    IRC::Log::Mode
    IRC::Log::Nick-Change
    IRC::Log::Topic

=head3 conversation

Returns C<True> if this entry is part of a conversation.  Else, it returns
C<False>.

These entry types are considered conversational messages:

    IRC::Log::Message
    IRC::Log::Self-Reference
    IRC::Log::Topic

=head3 date

The C<Date> of this entry.

=head3 entries

The C<entries> of the C<log> of this entry.

=head3 gist

Create the string representation of the entry as it originally occurred
in the log.

=head3 hhmm

A string representation of the hour and the minute of this entry ("hhmm").

=head3 hh-mm

A string representation of the hour and the minute of this entry ("hh:mm").

=head3 hour

The hour (in UTC) the entry was added to the log.

=head3 log

The C<IRC::Log> object of which this entry is a part.

=head3 message

The text representation of the entry.

=head3 minute

The minute (in UTC) the entry was added to the log.

=head3 next

The next entry in this log (if any).

=head3 nick

The nick of the user that originated the entry in the log.

=head3 ordinal

Zero-based ordinal number of this entry within the minute it occurred.

=head3 pos

The position of this entry in the C<entries> of the C<log> of this entry.

=head3 prefix

The prefix used in creating the C<gist> of this entry.

=head3 prev

The previous entry in this log (if any).

=head3 problems

The C<problems> of the C<log> of this entry.

=head3 sender

A representation of the sender.  The same as C<nick> for the C<Message>
class, otherwise the empty string as then the nick is encoded in the
C<message>.

=head3 target

Representation of an anchor in an HTML-file for deep linking to this
entry.  Can also be used as a sort key across entries from multiple
dates.

=head2 IRC::Log::Joined

No other methods are provided.

=head2 IRC::Log::Left

No other methods are provided.

=head2 IRC::Log::Kick

=head3 kickee

The nick of the user that was kicked in this log entry.

=head3 spec

The specification with which the user was kicked in this log entry.

=head2 IRC::Log::Message

=head3 text

The text that the user entered that resulted in this log entry.

=head2 IRC::Log::Mode

=head3 flags

The flags that the user entered that resulted in this log entry.

=head3 nicks

An array of nicknames (to which the flag setting should be applied)
that the user entered that resulted in this log entry.

=head2 IRC::Log::Nick-Change

=head3 new-nick

The new nick of the user that resulted in this log entry.

=head2 IRC::Log::Self-Reference

=head3 text

The text that the user entered that resulted in this log entry.

=head2 IRC::Log::Topic

=head3 text

The new topic that the user entered that resulted in this log entry.

=head1 AUTHOR

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/IRC-Log .
Comments and Pull Requests are welcome.

=head1 COPYRIGHT AND LICENSE

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
