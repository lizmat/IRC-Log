use Array::Sorted::Util:ver<0.0.11+>:auth<zef:lizmat>;
use has-word:ver<0.0.6+>:auth<zef:lizmat>;

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

my sub hmon2heartbeat(uint32 $hmon) {
    ($hmon +> 27 +&  0x001f) * 60 + ($hmon +> 21 +& 0x003f)
}

my sub target2hmo(str $target) {
    $target.chars == 21  # yyyy-mm-ddZhh:mm-oooo
      ?? hmo(+$target.substr(11,2), +$target.substr(14,2), +$target.substr(17))
      !! hm( +$target.substr(11,2), +$target.substr(14,2))
}

#-------------------------------------------------------------------------------
# Expected message types

role IRC::Log::Entry {
    has $.log is built(:bind);
    has uint32 $!hmon;

    submethod TWEAK(int :$hour, int :$minute, int :$ordinal, str :$nick) {
        given $!log {
            my $nick-index := .nick-indices{$nick};
            unless $nick-index.defined {
                .nick-indices{$nick} := $nick-index := .nick-names.elems;
                .nick-names.push: $nick;
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
    method heartbeat()  { hmon2heartbeat  $!hmon }
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
    method Str() { self.gist }
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

role IRC::Log:ver<0.0.25>:auth<zef:lizmat> {
    has Date   $.Date  is built(False);
    has str    $.date  is built(False);
    has str    $.raw   is built(False);
    has uint32 @.hmons is built(False);  # list of "coordinates"
    has str    @.nick-names   is built(False);  # unsorted array of nicks
    has        %.nick-indices is built(False);  # hash with nick name -> index
    has        $.entries  is built(False);  # IterationBuffer of entries
    has        $.problems is built(False);  # IterationBuffer of problem pairs
    has        $.last-topic-change is rw is built(False);
    has uint32 $.nr-conversation-entries is built(False);
    has uint32 $.nr-control-entries      is built(False);
    has str    $.first-target is built(False);
    has str    $.last-target  is built(False);
    has        %!state;       # hash with final state of internal parsing

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
        @!nick-names = "";      # nick name indices are 1-based
        %!nick-indices{""} = 0;

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
        %!nick-indices{$nick} // Nil
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

    method gist() { self.List.join("\n") ~ "\n" }
    method Str()  { self.gist }
    method List() { $!entries.List.map(*.gist).List }

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
                     $_ if .conversation given $!entries[$pos]
                 }
              !! -> int $pos {
                     $_ unless .conversation given $!entries[$pos]
                 }
        }
        orwith $control {
            $seq := $seq.map: $control
              ?? -> int $pos {
                     $_ if .control given $!entries[$pos]
                 }
              !! -> int $pos {
                     $_ unless .control given $!entries[$pos]
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

    proto method update(|) {*}
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
                @!hmons        = ();
                $!entries     := IterationBuffer.CREATE;
                $!problems    := IterationBuffer.CREATE;
                @!nick-names   = "";  # nick name indices are 1-based
                %!nick-indices = "" => 0;

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
        if $!entries.elems {
            $!first-target = $!entries.head.target;
            $!last-target  = $!entries.tail.target;
        }

        # return new entries
        $!entries.Seq.skip($initial-nr-entries)
    }

    multi sub infix:<eqv>(
      IRC::Log::Entry:D $left,
      IRC::Log::Entry:D $right
    --> Bool:D) {
        $left.^name eq $right.^name
          && $left.heartbeat == $right.heartbeat
          && $left.message   eq $right.message
    }

    method EXPORT() { Map.new: '&infix:<eqv>' => &infix:<eqv> }
}

# vim: expandtab shiftwidth=4
