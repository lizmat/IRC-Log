use Array::Sorted::Util:ver<0.0.8>:auth<zef:lizmat>;

# The compressed "coordinates" of an entry (hour, minute, ordinal, nick-index)
# or short "hmon", are stored as an unsigned 32bit value, allowing for 512
# messages within a minute, and up to 4K - 1 different nicks in a (daily) log.
# 1111 1000 0000 0000 0000 0000 0000 0000  hour
#       111 1110 0000 0000 0000 0000 0000  minute
#              1 1111 1111 0000 0000 0000  ordinal
#                          1111 1111 1111  nick-index
#
# Storing coordinates like this in a list, creates a sorted list that can
# be quickly searched for a given target, but which can also be easily
# traversed to produce the entries of a given nick-index (without needing
# to actually access the message entry object itself).

# The following mnemonics apply
#
#  hmon - the full compressed hour / minute / ordinal / nick-index informtion
#  hmo  - just the compressed hour / minute / ordinal info (nick-index is 0)
#  hm   - just the compressed hour / minute info (ordinal / nick-index are 0)

# Helper subs for conversions
my sub hm(int $hour, int $minute --> uint32) {
    $hour +< 27 + $minute +< 21
}
my sub hmo(int $hour, int $minute, int $ordinal --> uint32) {
    $hour +< 27 + $minute +< 21 + $ordinal +< 12
}
my sub hmon(int $hour, int $minute, int $ordinal, int $nick-index --> uint32) {
    $hour +< 27 + $minute +< 21 + $ordinal +< 12 + $nick-index
}
my sub hmon2hmo(       uint32 $hmon) { $hmon       +& 0x0fffff000 }
my sub hmon2hour(      uint32 $hmon) { $hmon +> 27 +&      0x001f }
my sub hmon2minute(    uint32 $hmon) { $hmon +> 21 +&      0x003f }
my sub hmon2ordinal(   uint32 $hmon) { $hmon +> 12 +&      0x01ff }
my sub hmon2nick-index(uint32 $hmon) { $hmon       +&      0x0fff }

my sub target2hmo(str $target) {
    $target.chars == 21  # yyyy-mm-ddZhh:mm-oooo
      ?? hmo(+$target.substr(11,2), +$target.substr(14,2), +$target.substr(17))
      !! hm( +$target.substr(11,2), +$target.substr(14,2))
}

role IRC::Log:ver<0.0.16>:auth<zef:lizmat> {
    has str    $.date       is built(False);
    has str    $.raw        is built(False);
    has uint32 @.hmons      is built(False);  # list of "coordinates"
    has str    @.nick-names is built(False);  # unsorted array of nicks
    has        $.entries    is built(False);  # IterationBuffer of entries
    has        $.problems   is built(False);  # IterationBuffer of problem pairs
    has Int    $.nr-control-entries is rw      is built(False);
    has Int    $.nr-conversation-entries is rw is built(False);
    has        $.last-topic-change is rw       is built(False);
    has        %!state;  # hash with final state of internal parsing

#-------------------------------------------------------------------------------
# Main log parser logic

    method parse-log(::?CLASS:D:
      str $text,
          $last-hour    is raw,
          $last-minute  is raw,
          $ordinal      is raw,
          $linenr       is raw,
    ) is implementation-detail {
        ...
    }

#-------------------------------------------------------------------------------
# Class methods

    method IO2Date(::?CLASS:U: IO:D $path) {
        try $path.basename.split(".").head.Date
    }

    proto method new(|) {*}
    multi method new(::?CLASS:U: IO:D $path) {
        self.new: $path.slurp(:enc("utf8-c8")), self.IO2Date($path)
    }

    multi method new(::?CLASS:U: IO:D $path, Date() $Date) {
        self.new: $path.slurp(:enc("utf8-c8")), $Date
    }

    method !INIT($text, $Date) {
        $!date       = $Date.Str;
        $!entries   := IterationBuffer.CREATE;
        $!problems  := IterationBuffer.CREATE;
        @!nick-names = "";  # nick name indices are 1-based

        self.parse($text);
        self
    }

    multi method new(::?CLASS:U: Str:D $text, Date() $Date) {
        self.CREATE!INIT($text, $Date)
    }

#-------------------------------------------------------------------------------
# Instance methods

    method first-entry(::?CLASS:D:) { $!entries[0] }
    method last-entry( ::?CLASS:D:) { $!entries[$!entries.elems - 1] }

    method first-target(::?CLASS:D:) { $!entries[0].target }
    method last-target( ::?CLASS:D:) { $!entries[$!entries.elems - 1].target }

    method target-index(::?CLASS:D: Str:D $target) {
        my uint32 $hmo = target2hmo($target);
        my $pos := finds @!hmons, $hmo;
        hmon2hmo(@!hmons[$pos]) == $hmo ?? $pos.Int !! Nil
    }

    method target-entry(::?CLASS:D: Str:D $target) {
        my uint32 $hmo = target2hmo($target);
        my $pos := finds @!hmons, $hmo;
        hmon2hmo(@!hmons[$pos]) == $hmo ?? $!entries[$pos] !! Nil
    }

    method entries-lt-target(::?CLASS:D: Str:D $target) {
        with self.target-index($target) -> $pos {
            $!entries.Seq.head($pos) if $pos
        }
    }

    method entries-le-target(::?CLASS:D: Str:D $target) {
        with self.target-index($target) -> $pos {
            $!entries.Seq.head($pos + 1)
        }
    }

    method entries-ge-target(::?CLASS:D: Str:D $target) {
        with self.target-index($target) -> $pos {
            $!entries.Seq.skip($pos) if $pos < $!entries.elems
        }
    }

    method entries-gt-target(::?CLASS:D: Str:D $target) {
        with self.target-index($target) -> $pos {
            $!entries.Seq.skip($pos + 1) if $pos < $!entries.elems - 1
        }
    }

    method !index-of-nick(::?CLASS:D: str $nick) {
        @!nick-names.first(* eq $nick, :k)
    }
    method entries-of-nick(::?CLASS:D: str $nick) {
        my int $index = self!index-of-nick($nick);
        (^@!hmons).map: -> int $pos {
            $!entries[$pos] if hmon2nick-index(@!hmons[$pos]) == $index
        }
    }
    method entries-of-nicks(::?CLASS:D: @nicks) {
        my $mask = 0;
        for @nicks -> str $nick {
            $mask = $mask +| (1 +< $_)
              with self!index-of-nick($nick);
        }
        if $mask {   # at least one nick found
            (^@!hmons).map: -> int $pos {
                $!entries[$pos]
                  if $mask +& (1 +< hmon2nick-index(@!hmons[$pos]))
            }
        }
    }

    multi method update(::?CLASS:D: IO:D $path) {
        self.parse($path.slurp(:enc("utf8-c8")))
    }
    multi method update(::?CLASS:D: Str:D $text) {
        $!raw && $!raw eq $text
          ?? Empty
          !! self.parse($text)
    }

#-------------------------------------------------------------------------------
# Public private methods

    method parse(::?CLASS:D: str $text) is implementation-detail {
        my str $to-parse;
        my int $last-hour;
        my int $last-minute;
        my int $ordinal;
        my int $linenr;

        # done a parse before for this object
        if %!state -> %state {

            # adding new lines on log
            if $text.starts-with($!raw) {
                $last-hour   = %state<last-hour>;
                $last-minute = %state<last-minute>;
                $ordinal     = %state<ordinal>;
                $linenr      = %state<linenr>;
                $to-parse    = $text.substr($!raw.chars);
            }

            # log appears to be altered, run it from scratch!
            else {
                @!hmons      = ();
                $!entries   := IterationBuffer.CREATE;
                $!problems  := IterationBuffer.CREATE;
                @!nick-names = "";  # nick name indices are 1-based

                $!nr-control-entries      = 0;
                $!nr-conversation-entries = 0;
                $!last-topic-change       = Nil;

                $last-hour = $last-minute = $linenr = -1;
                $to-parse  = $text;
            }
        }

        # first parse
        else {
            $last-hour = $last-minute = $linenr = -1;
            $to-parse  = $text;
        }

        my int $initial-nr-entries = $!entries.elems;
        self.parse-log(
          $to-parse, $last-hour, $last-minute, $ordinal, $linenr
        );

        # save current state in case of updates
        $!raw   = $text;
        %!state = :$last-hour, :$last-minute, :$ordinal, :$linenr;

        # return new entries
        $!entries.Seq.skip($initial-nr-entries)
    }
}

#-------------------------------------------------------------------------------
# Expected message types

role IRC::Log::Entry {
    has $.log is built(:bind);
    has uint32 $!hmon;

    method TWEAK(int :$hour, int :$minute, int :$ordinal, str :$nick) {
        given $!log {
            my @nick-names := .nick-names;
            my $nick-index := @nick-names.first(* eq $nick, :k);
            without $nick-index {
                $nick-index := @nick-names.elems;
                @nick-names.push: $nick;
                die "Too many nicks" if $nick-index > 0x0fff;  # 4K max
            }

            .entries.push: self;
            .hmons.push: $!hmon = hmon($hour, $minute, $ordinal, $nick-index);
            ++.nr-control-entries      if self.control;
            ++.nr-conversation-entries if self.conversation;
        }
    }

    method target() {
        my int $hour    = $.hour;
        my int $minute  = $.minute;
        my int $ordinal = $.ordinal;
        my str $date    = $.date.Str;  # XXX workaround Rakudo issue

        my $target = $date
          ~ 'Z'
          ~ ($hour < 10 ?? "0$hour" !! $hour)         # cheap sprintf
          ~ ':'
          ~ ($minute < 10 ?? "0$minute" !! $minute);  # cheap sprintf

        $ordinal
          ?? $target ~ '-' ~ ($ordinal < 10           # cheap sprintf
            ?? "000$ordinal"
            !! $ordinal < 100
              ?? "00$ordinal"
              !! $ordinal < 1000
                ?? "0$ordinal"
                !! $ordinal
            )
          !! $target
    }

    method hour()       { hmon2hour       $!hmon }
    method minute()     { hmon2minute     $!hmon }
    method ordinal()    { hmon2ordinal    $!hmon }
    method nick-index() { hmon2nick-index $!hmon }
    method nick()       { $!log.nick-names[hmon2nick-index $!hmon] }
    method pos()        { finds $!log.hmons, $!hmon +& 0x0ffffffff }
#                                      Rakudo issue ^^^^^^^^^^^^^^

    method date()     { $!log.date     }
    method entries()  { $!log.entries  }
    method problems() { $!log.problems }

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
    method message() { "$.nick joined" }
}
class IRC::Log::Left does IRC::Log::Entry {
    method message() { "$.nick left" }
}
class IRC::Log::Kick does IRC::Log::Entry {
    has Str $.kickee is built(:bind);
    has Str $.spec   is built(:bind);

    method message() { "$!kickee was kicked by $.nick $!spec" }
}
class IRC::Log::Message does IRC::Log::Entry {
    has Str $.text is built(:bind);

    method gist() { '[' ~ self.hh-mm ~ '] <' ~ $.nick ~ '> ' ~ $.message }
    method sender() { $.nick }
    method message() { $!text }
    method prefix(--> '') { }
    method control(    --> False) { }
    method conversation(--> True) { }
}
class IRC::Log::Mode does IRC::Log::Entry {
    has Str $.flags is built(:bind);
    has Str @.nicks is built(:bind);

    method message() { "$.nick sets mode: $!flags @.nicks.join(" ")" }
}
class IRC::Log::Nick-Change does IRC::Log::Entry {
    has Str $.new-nick is built(:bind);

    method message() { "$.nick is now known as $!new-nick" }
}
class IRC::Log::Self-Reference does IRC::Log::Entry {
    has Str $.text is built(:bind);

    method prefix(--> '* ') { }
    method message() { "$.nick $!text" }
    method control(    --> False) { }
    method conversation(--> True) { }
}
class IRC::Log::Topic does IRC::Log::Entry {
    has Str $.text is built(:bind);

    method message() { "$.nick changes topic to: $!text" }
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

=end code

=head1 DESCRIPTION

IRC::Log provides a role providing an interface to IRC logs in various
formats.  Each log is supposed to contain all messages from a given
date.

The C<parse-log> method must be provided by the consuming class.

=head1 METHODS TO BE PROVIDED BY CONSUMER

=head2 parse-log

=begin code :lang<raku>

    method parse-log(
      str $text,
          $last-hour   is raw,
          $last-minute is raw,
          $ordinal     is raw,
          $linenr      is raw,
    --> Nil) {
        ...
    }

=end code

The C<parse-log> instance method should be provided by the consuming class.
Examples of the implementation of this method can be found in the
C<IRC::Log::Colabti> and C<IRC::Log::Textual> modules.

It is supposed to take 5 positional parameters that are assumed to be
correctly updated by the logic in the C<.parse-log> method.

=item the text to be parsed

The (partial) log to be parsed.

=item the last hour seen as a raw integer

An C<is raw> variable that contains the last hour value seen in messages.
It is set to -1 the first time, so that it is always unequal to any hour
value that will be encountered.

=item the last minute seen as a raw integer

An C<is raw> variable that contains the last minute value seen in messages.
It is set to -1 the first time, so that it is always unequal to any minute
value that will be encountered.

=item the last ordinal seen as a raw integer

An C<is raw> variable that contains the last ordinal value seen in messages.
It is set to 0 the first time.

=item the line number of the line last parsed

An C<is raw> variable that contains the line number last parsed in the log.
It is set to -1 the first time, so that the first line parsed will be 0.

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

=head2 date

=begin code :lang<raku>

say $log.date;

=end code

The C<date> instance method returns the C<Date> object for this log.

=head2 entries

=begin code :lang<raku>

.say for $log.entries.List;                       # all entries

.say for $log.entries.List.grep(*.conversation);  # only actual conversation

=end code

The C<entries> instance method returns an C<IterationBuffer> with entries from
the log.  It contains instances of one of the following classes:

    IRC::Log::Joined
    IRC::Log::Left
    IRC::Log::Kick
    IRC::Log::Message
    IRC::Log::Mode
    IRC::Log::Nick-Change
    IRC::Log::Self-Reference
    IRC::Log::Topic

=head2 entries-ge-target

=begin code :lang<raku>

.say for $log.entries-ge-target($target);

=end code

The C<entries-from-target> instance method returns all entries that are
C<after> B<and> including the given target.

=head2 entries-gt-target

=begin code :lang<raku>

.say for $log.entries-gt-target($target);

=end code

The C<entries-gt-target> instance method returns all entries that are
C<after> (so B<not> including) the given target.

=head2 entries-le-target

=begin code :lang<raku>

.say for $log.entries-le-target($target);

=end code

The C<entries-le-target> instance method returns all entries that are
C<before> B<and> including the given target.

=head2 entries-lt-target

=begin code :lang<raku>

.say for $log.entries-lt-target($target);

=end code

The C<entries-lt-target> instance method returns all entries that are
C<before> (so B<not> including) the given target.

=head2 entries-of-nick

=begin code :lang<raku>

.say for $log.entries-of-nick($nick);

=end code

The C<entries-of-nick> instance method takes a C<nick> as parameter and
returns a C<Seq> consisting of the entries of the given nick (if any).

=head2 entries-of-nicks

=begin code :lang<raku>

.say for $log.entries-of-nicks(@nicks);

=end code

The C<entries-of-nicks> instance method takes a list of C<nicks> and
returns a C<Seq> consisting of the entries of the given nicks (if any).

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

=head2 nick-names

=begin code :lang<raku>

.say for $log.nick-names;

=end code

The C<nick-names> instance method returns a native str array with the
nick names that have been found in the order they were found.

=head2 nicks

=begin code :lang<raku>

for $log.nicks -> (:key($nick), :value($entries)) {
    say "$nick has $entries.elems() entries";
}

=end code

The C<nicks> instance method returns a C<Map> with the nicks seen for this
log as keys (in the order they were seen_, and an C<IterationBuffer> with
entries that originated by that nick.

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

.say for $log.problems.List;

=end code

The C<problems> instance method returns an C<IterationBuffer> with C<Pair>s
of lines that could B<not> be interpreted in the log.  The key is a string
with the line number and a reason it could not be interpreted.  The
value is the actual line.

=head2 raw

=begin code :lang<raku>

say "contains 'foo'" if $log.raw.contains('foo');

=end code

The C<raw> instance method returns the raw text version of the log.  It can
e.g. be used to do a quick check whether a string occurs in the raw text,
before checking C<entries> for a given string.

=head2 target-entry

=begin code :lang<raku>

say "$target has $_" with $log.target-entry($target);

=end code

The C<target-entry> returns the B<entry> of the specified target, or it
returns C<Nil> if the entry of the target could not be found.

=head2 target-index

=begin code :lang<raku>

say "$target at $_" with $log.target-index($target);

=end code

The C<target-index> returns the B<position> of the specified target in the
list of C<entries>, or it returns C<Nil> if the target could not be found.

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

The C<entries> of the C<log> of this entry as an C<IterationBuffer>.

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

=head3 nick-index

The index of the nick in the list of C<nick-names> in the log.

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
