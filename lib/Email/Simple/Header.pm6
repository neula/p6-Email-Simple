unit class Email::Simple::Header;

grammar Email::Simple::Header::Grammar {
	token TOP($*crlf) { <head>+ }
	token head		{ ^^[ <field>\: <body> ] | <invalid> }
	#Printable ascii-range except colon
	token field	{ <[\x[21]..\x[39]] + [\x[3B]..\x[7E]]>+ }
	token body		{ <indent>? <notcrlf>? <crlf> <folded>* }
	token folded	{ ^^ <indent> <notcrlf> <crlf> }
	token crlf {
		| <?{ $*crlf ~~ Str:D }> $*crlf
		| <?{ $*crlf ~~ Any }> [ [\x[0D]\x[0A]]
								 | [\x[0A]\x[0D] <.warnlfcr> ]
								 | [ \x[0A] <.warnlf> ]
								 | [ \x[0D] <.warncr> ]
							   ]
	}
	token invalid	{ ^^ <notcrlf> <crlf> }
	token notcrlf	{ <-crlf>+ }
	token warnlfcr	{ <?> }
	token warnlf	{ <?> }
	token warncr	{ <?> }
	token indent	{ \h+ }
}

class Email::Simple::Header::Actions {
	method TOP($/) {
		make $/.<head>.map( *.made).grep( * ~~ Array:D ).Array;
	}
	method head($/) {
		make [ $/.<field>.Str, $/.<body>.made ] unless $/.<invalid>;
	}
	#TODO: Figure out what to do here
	method invalid($/) {
	}
	method body($/) {
		make ($/.<notcrlf>.so ?? [ $/.<notcrlf>.Str ] !! [] ).append(
			$/.<folded>.map: *.made).join(" ");
	}
	method folded($/) {
		make $/.<notcrlf>.Str;
	}
}

has $.header-matches;
has $.crlf;

has @.headers-added;

multi method new(Str $header-text, :$crlf) {
	my $parsed;
	with $crlf {
		$parsed = Email::Simple::Header::Grammar.parse(
			$header-text,
			actions => Email::Simple::Header::Actions,
			:args(($crlf).List));
	} else {
		$parsed = Email::Simple::Header::Grammar.parse(
			$header-text,
			actions => Email::Simple::Header::Actions);
	}
	my $found-crlf;
	for $parsed.<head> {
		next without .<body>;
		$found-crlf = $_.Str with .<body>.<crlf>;
	}
	self.bless(header-matches => $parsed, crlf => $found-crlf );
}

multi method new (Array $headers, Str :$crlf = "\x0d\x0a") {
	if $headers[0] ~~ Array {
		self.bless(crlf => $crlf, headers-added => $headers);
	}
	elsif $headers[0] ~~ Pair {
		self.bless(crlf => $crlf, headers-added => $headers.map(*.kv));
	}
	else {
		my @folded-headers;
		loop (my $x=0;$x < +$headers;$x+=2) {
			@folded-headers.push([$headers[$x], $headers[$x+1]]);
		}

		self.bless(crlf => $crlf, headers-added => @folded-headers);
	}
}

method headers(--> Array) is rw {
	with $!header-matches {
		$!header-matches.made;
	} else {
		@!headers-added;
	}
}

method as-string {
	my $header-str;

	for @.headers {
		my $header = $_[0] ~ ': ' ~ $_[1];
		$header-str ~= self!fold($header);
	}

	return $header-str;
}
method Str { self.as-string }

method header-names {
	my @names = gather {
		for @.headers {
			take $_[0];
		}
	}

	return @names;
}

method header-pairs {
	@.headers
}

method header (Str $name, :$multi) {
	my @values = gather {
		for @.headers {
			if lc($_[0]) eq lc($name) {
				take $_[1];
			}
		}
	}

	if +@values {
		if $multi {
			return @values;
		}
		else {
			return @values[0];
		}
	} else {
		return Nil;
	}
}

method header-set ($field, *@values) {
	my @indices;
	my $x = 0;
	for @.headers {
		if lc($_[0]) eq lc($field) {
			push(@indices, $x);
		}
		$x++;
	}

	if +@indices > +@values {
		my $overage = +@indices - +@values;
		for 1..$overage {
			@.headers.splice(@indices[*-1],1);
			@indices.pop();
		}
	} elsif +@values > +@indices {
		my $underage = +@values - +@indices;
		for 1..$underage {
			@.headers.push([$field, '']);
			@indices.push(+@.headers-1);
		}
	}

	for 0..(+@indices - 1) {
		@.headers[@indices[$_]] = [$field, @values[$_]];
	}

	if +@values {
		return @values;
	} else {
		return Nil;
	}
}

method !fold (Str $line is copy) {
	my $limit = self!default-fold-at - 1;

	if $line.chars <= $limit {
		return $line ~ self.crlf;
	}

	my $folded;
	while $line.chars {
		if $line ~~ s/^(.{0,$limit})\s// {
			$folded ~= $1 ~ self.crlf;
			if $line.chars {
				$folded ~= self!default-fold-indent;
			}
		} else {
			$folded ~= $line ~ self.crlf;
			$line = '';
		}
	}

	return $folded;
}
method !default-fold-at { 78 }
method !default-fold-indent { " " }

# vim: ft=perl6 sw=4 ts=8 noexpandtab smarttab
