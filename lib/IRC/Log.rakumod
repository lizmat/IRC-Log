use Array::Sorted::Util:ver<0.0.8>:auth<zef:lizmat>;
use has-word:ver<0.0.1>:auth<zef:lizmat>;

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

role IRC::Log:ver<0.0.18>:auth<zef:lizmat> {
    has Date   $.Date       is built(False);
    has str    $.date       is built(False);
    has str    $.raw        is built(False);
    has uint32 @.hmons      is built(False);  # list of "coordinates"
    has str    @.nick-names is built(False);  # unsorted array of nicks
    has        $.entries    is built(False);  # IterationBuffer of entries
    has        $.problems   is built(False);  # IterationBuffer of problem pairs
    has        $.last-topic-change is rw is built(False);
    has uint32 $.nr-conversation-entries is built(False);
    has uint32 $.nr-control-entries      is built(False);
    has str    $.first-target is built(False);
    has str    $.last-target  is built(False);
    has        %!state;  # hash with final state of internal parsing

#-------------------------------------------------------------------------------
# Main log parser logic

    method parse-log(::?CLASS:D:
      str $text,
          $last-hour               is raw,
          $last-minute             is raw,
          $ordinal                 is raw,
          $linenr                  is raw,
          $nr-control-entries      is raw,
          $nr-conversation-entries is raw,
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
        $!Date      := $Date;
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

    method !index-of-nick(str $nick) {
        @!nick-names.first(* eq $nick, :k)
    }
    method entries-of-nick(::?CLASS:D: str $nick) {
        with self!index-of-nick($nick) -> int $index {
            (^@!hmons).map: -> int $pos {
                $!entries[$pos] if hmon2nick-index(@!hmons[$pos]) == $index
            }
        }
    }
    method !nicks-mask(@nicks) {
        my $mask = 0;
        for @nicks -> str $nick {
            $mask = $mask +| (1 +< $_)
              with self!index-of-nick($nick);
        }
        $mask
    }
    method entries-of-nick-names(::?CLASS:D: @nick-names) {
        if self!nicks-mask(@nick-names) -> $mask {   # at least one nick found
            (^@!hmons).map: -> int $pos {
                $!entries[$pos]
                  if $mask +& (1 +< hmon2nick-index(@!hmons[$pos]))
            }
        }
    }

    method search(::?CLASS:D:
      :$all,                    # modifier on :contains / :words / :starts-with
      :$contains,               # messages containing given string(s)
      :$control,                # just control messages
      :$conversation is copy,   # just conversational messages
      :$ge-target    is copy,   # messages after given target inclusive
      :$gt-target    is copy,   # messages after given target
      :$ignorecase,             # modifier on :contains / :words / :starts-with
      :$le-target    is copy,   # messages before given target inclusive
      :$lt-target    is copy,   # messages before given target
      :&matches,                # messages matching a regex
      :$nick-names,             # messages by given nick name(s)
      :$reverse,                # produce results in reverse order
      :$starts-with,            # messages starting with given string(s)
      :$targets,                # messages matching these targets
      :$words,                  # messages containing given word(s)
    ) {

        # short-circuit if any target out of range
        if $lt-target || $le-target -> str $target {
            return Empty                  if $target lt $!first-target;
            $lt-target = $le-target = Nil if $target gt $!last-target;
        }
        if $ge-target || $gt-target -> str $target {
            return Empty                  if $target gt $!last-target;
            $ge-target = $gt-target = Nil if $target lt $!first-target;
        }

        # short-circuit if there's no text for this to be found, set
        # conversation flag if there is something to be searched for
        my @needles;
        my $needles;
        if $contains || $starts-with || $words -> $string {
            @needles  = $string.words;  # save for later
            $needles := @needles.elems;

            if $all {
                return Empty
                  unless $!raw.contains($_, :$ignorecase)
                  for @needles;
            }
            else {
                return Empty
                  unless @needles.first: { $!raw.contains($_, :$ignorecase) }
            }
            $conversation = True;
        }
        elsif &matches.defined {
            $conversation = True;
        }

        # set up initial Seq of indices of entries to be checked
        my $seq;
        if $lt-target || $le-target -> str $target {
            with self.target-index($target) -> int $pos is copy {
                --$pos if $lt-target;
                $seq := 0 .. $pos if $pos >= 0;
            }
            return Empty without $seq;

            if $ge-target || $gt-target -> str $target {
                with self.target-index($target) -> int $pos is copy {
                    ++$pos if $gt-target;
                    if $pos > $seq.min {
                        $pos <= $seq.max
                          ?? ($seq := $pos .. $seq.max)
                          !! (return Empty)
                    }
                }
            }
            $seq := $seq.reverse if $reverse;
        }
        elsif $ge-target || $gt-target -> str $target {
            with self.target-index($target) -> int $pos is copy {
                ++$pos if $gt-target;
                $seq := $pos ..^ @!hmons if $pos < @!hmons;
            }

            return Empty without $seq;
            $seq := $seq.reverse if $reverse;
        }
        elsif $targets {
            if $targets.map( -> str $target {
                if $target.starts-with($!date) {
                    $_ with self.target-index($target)
                }
            }) -> @pos {
                $seq := $reverse ?? @pos.sort(-*) !! @pos.sort;
            }
            else {
                return Empty;
            }
        }
        else {
            $seq := $reverse ?? (^@!hmons).reverse !! ^@!hmons
        }

        # limit to nick(s) on the hmon values of the indices
        if $nick-names {
            if $nick-names ~~ List {
                with self!nicks-mask($nick-names.list) -> $mask {
                    $seq := $seq.map: -> int $pos {
                        $pos if $mask +& (1 +< hmon2nick-index(@!hmons[$pos]))
                    }
                }
                else {
                    return Empty;
                }
            }
            else {
                with self!index-of-nick($nick-names) -> int $index {
                    $seq := $seq.map: -> int $pos {
                        $pos if hmon2nick-index(@!hmons[$pos]) == $index
                    }
                }
                else {
                    return Empty;
                }
            }
        }

        # convert indices to entries, while filtering if necessary
        with $conversation {
            $seq := $seq.map: $conversation
              ?? -> int $pos {
                     given $!entries[$pos] { $_ if .conversation }
                 }
              !! -> int $pos {
                     given $!entries[$pos] { $_ unless .conversation }
                 }
        }
        orwith $control {
            $seq := $seq.map: $control
              ?? -> int $pos {
                     given $!entries[$pos] { $_ if .control }
                 }
              !! -> int $pos {
                     given $!entries[$pos] { $_ unless .control }
                 }
        }
        else {
            $seq := $seq.map: -> int $pos { $!entries[$pos] }
        }

        if $needles {
            my $message;
            my &matcher := $contains
              ?? $all
                ?? -> str $needle {
                       $message.contains($needle, :$ignorecase).not
                   }
                !! -> str $needle {
                       $message.contains($needle, :$ignorecase)
                   }
              !! $starts-with
                ?? $all
                  ?? -> str $needle {
                         $message.starts-with($needle, :$ignorecase).not
                     }
                  !! -> str $needle {
                         $message.starts-with($needle, :$ignorecase)
                     }
                !! $all # and $words
                  ?? -> str $needle {
                         has-word($message, $needle, :$ignorecase).not
                     }
                  !! -> str $needle {
                         has-word($message, $needle, :$ignorecase)
                     }

            $seq := $all
              ?? $seq.map: {
                     $message := .message;
                     $_ unless @needles.first(&matcher)
                 }
              !! $seq.map: {
                     $message := .message;
                     $_ if     @needles.first(&matcher)
                 }
        }
        elsif &matches.defined {
            $seq := $seq.map: { $_ if .message.contains(&matches) }
        }

        $seq
    }

    multi method update(::?CLASS:D: IO:D $path) {
        self.parse($path.slurp(:enc("utf8-c8")))
    }
    multi method update(::?CLASS:D: Str:D $text) {
        self.parse($text)
    }

#-------------------------------------------------------------------------------
# Public private methods

    method parse(::?CLASS:D: str $text) is implementation-detail {
        my str $to-parse;
        my int $last-hour;
        my int $last-minute;
        my int $ordinal;
        my int $linenr;

        # nothing to do?
        return Empty if $!raw && $!raw eq $text;

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
          $to-parse, $last-hour, $last-minute, $ordinal, $linenr,
          $!nr-control-entries, $!nr-conversation-entries,
        );

        # save current state in case of updates
        $!raw   = $text;
        %!state = :$last-hour, :$last-minute, :$ordinal, :$linenr;
        $!first-target = $!entries.head.target;
        $!last-target  = $!entries.tail.target;

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
                die "Too many nick names" if $nick-index > 0x0fff;  # 4K max
            }

            .entries.push: self;
            .hmons.push: $!hmon = hmon($hour, $minute, $ordinal, $nick-index);
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
    has Str $.flags      is built(:bind);
    has Str @.nick-names is built(:bind);

    method message() { "$.nick sets mode: $!flags @.nick-names.join(" ")" }
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
          $last-hour               is raw,
          $last-minute             is raw,
          $ordinal                 is raw,
          $linenr                  is raw,
          $nr-control-entries      is raw,
          $nr-conversation-entries is raw,
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
          $last-hour               is raw,
          $last-minute             is raw,
          $ordinal                 is raw,
          $linenr                  is raw,
          $nr-control-entries      is raw,
          $nr-conversation-entries is raw,
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

=item the number of control messages seen

An C<is raw> variable that needs to be incremented whenever a control
message is created.

=item the number of conversation messages seen

An C<is raw> variable that needs to be incremented whenever a conversation
message is created.

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

dd $log.date;  # "2021-04-22"

=end code

The C<date> instance method returns the string of the date of the log.

=head2 Date

=begin code :lang<raku>

dd $log.Date;  # Date.new(2021,4,22)

=end code

The C<Date> instance method returns the date of the log as a C<Date> object..

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

=head2 entries-of-nick-names

=begin code :lang<raku>

.say for $log.entries-of-nick-names(@nick-names);

=end code

The C<entries-of-nick-names> instance method takes a list of C<nick-names>
and returns a C<Seq> consisting of the entries of the given nick names (if any).

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

=head2 search

=begin code :lang<raku>

.say for $channel.search;             # all entries in chronological order

.say for $channel.search(:reverse);   # all in reverse chronological order

.say for $channel.search(:control);            # control messages only

.say for $channel.search(:conversation);       # conversational messages only

.say for $channel.search(:matches(/ \d+ /);    # matching regex

.say for $channel.search(:starts-with<m:>);    # starting with text

.say for $channel.search(:contains<foo>);      # containing string

.say for $channel.search(:words<foo>);         # containing word

.say for $channel.search(:nick-names<lizmat timo>); # for one or more nick names

.say for $channel.search(:lt-target($target);  # entries before target

.say for $channel.search(:le-target($target);  # entries until target

.say for $channel.search(:ge-target($target);  # entries from target

.say for $channel.search(:gt-target($target);  # entries after target

.say for $channel.search(:@targets);           # entries of these targets

.say for $channel.search(
  :nick-names<lizmat japhb>,
  :contains<question answer>, :all,
);

=end code

The C<search> instance method provides a way to look for specific entries
in the log by zero or more criteria and modifiers.  The following criteria
can be specified:

=head3 all

Modifier.  Boolean indicating that if multiple words are specified with
C<contains>, C<starts-with> or C<words>, then B<all> words should match
to include the entry.

=head3 contains

A string consisting of one or more C<.words> that the C<.message> of an
entry should contain to be selected.  By default, any of the specified
words will cause an entry to be included, unless the C<all> modifier has
been specified with a C<True> value.  By default, string matching will be
case sensitive, unless the C<ignorecase> modifier has been specified with
a C<True> value.

Implies C<conversation> is specified with a C<True> value.

=head3 control

Boolean indicating to only include entries that return C<True> on their
C<.control> method.  Defaults to no filtering if not specified.

=head3 conversation

Boolean indicating to only include entries that return C<True> on their
C<.conversation> method.  Defaults to no filtering if not specified.

=head3 ge-target

A string indicating the C<.target> of an entry should be equal to, or later
than (alphabetically greater than or equal).  Specified target may be of a
different C<date> than of the log.

=head3 gt-target

A string indicating the C<.target> of an entry should be later than
(alphabetically greater than).  Specified target may be of a different C<date>
than of the log.

=head3 ignorecase

Modifier.  Boolean indicating that string checking with C<contains>,
C<starts-with> or C<words>, should be done case-insensitively if specified
with a C<True> value.

=head3 le-target

A string indicating the C<.target> of an entry should be equal to, or before
(alphabetically less than or equal).  Specified target may be of a different
C<date> than of the log.

=head3 lt-target

A string indicating the C<.target> of an entry should be before (alphabetically
less than).  Specified target may be of a different C<date> than of the log.

=head3 matches

A regular expression (aka C<Regex> object) that should match the C<.message>
of an entry to be selected.  Implies C<conversation> is specified with a
C<True> value.

=head3 nick-names

A string consisting of one or more nick names that should match the sender
of the entry to be included.

=head3 reverse

Modifier.  Boolean indicating to reverse the order of the selected entries.

=head3 starts-with

A string consisting of one or more C<.words> that the C<.message> of an
entry should start with to be selected.  By default, any of the specified
words will cause an entry to be included, unless the C<all> modifier has
been specified with a C<True> value.  By default, string matching will be
case sensitive, unless the C<ignorecase> modifier has been specified with
a C<True> value.

Implies C<conversation> is specified with a C<True> value.

=head3 targets

One or more target strings indicating the entries to be returned.  Will be
returned in ascending order, unless C<reverse> is specified with a C<True>
value.

=head3 words

A string consisting of one or more C<.words> that the C<.message> of an
entry should contain as a word (an alphanumeric string bounded by the non-
alphanumeric characters, or the beginning or end of the string) to be selected.
By default, any of the specified words will cause an entry to be included,
unless the C<all> modifier has been specified with a C<True> value.  By
default, string matching will be case sensitive, unless the C<ignorecase>
modifier has been specified with a C<True> value.

Implies C<conversation> is specified with a C<True> value.

=head2 target-entry

=begin code :lang<raku>

say "$target has $_" with $log.target-entry($target);

=end code

The C<target-entry> instance method returns the B<entry> of the specified
target, or it returns C<Nil> if the entry of the target could not be found.

=head2 target-index

=begin code :lang<raku>

say "$target at $_" with $log.target-index($target);

=end code

The C<target-index> instance method returns the B<position> of the specified
target in the list of C<entries>, or it returns C<Nil> if the target could
not be found.

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

=head3 nick-names

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
