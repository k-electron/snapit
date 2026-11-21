#!/usr/bin/env bash
# The docs check. It has two kinds of rules.
#
# The User Guide's one source (docs/UserGuide.md, bundled into the Editor helper and read on
# GitHub), against the checklist of spec flows in scripts/user-guide-checklist.txt. A section
# is `## <a id="id"></a>Title <!-- icon: symbol.name -->`; HTML comments, on one line or several,
# are not text. Every failure names the file and the line:
#   1. every section has an id and an icon, and each id is unique;
#   2. every in-window link (`](#id)`) names a section that exists;
#   3. every checklist section exists and mentions every term of its line;
#   4. a link goes to a section or to https://github.com/k-electron/snapit, nowhere else (the
#      guide is bundled and fetches nothing);
#   5. an image is a relative path into the docs images folder (`images/...`, from the guide).
# Flow 58 of the scripted run repeats 1 to 3 on the guide the helper actually loaded.
#
# Every Markdown file in the repo (build output, Cargo's target folder, .git and the agent
# worktrees excepted):
#   6. every relative link and image resolves to a file or folder that exists, reported as
#      file:line. Code spans and fenced code are skipped. A link with a scheme (https:, mailto:)
#      or to a place in the same page (#id) is not a file and is not looked up.
#
#   scripts/check-docs.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

exec perl -CSDA -e '
use strict; use warnings;
use File::Find; use File::Basename qw(dirname);
my ($guide, $checklist) = @ARGV;
my $failed = 0;
sub fail { print STDERR "error: $_[0]\n"; $failed = 1; }

open(my $g, "<:encoding(UTF-8)", $guide) or die "cannot read $guide";
my (%text, %title, %line_of, @order, $current, $in_comment);
my (@links, @images);   # [line, destination]
my $gn = 0;
while (my $raw = <$g>) {
  chomp $raw; $gn++;
  my $heading = !$in_comment && $raw =~ /^## <a id="([a-z0-9-]+)"><\/a>(.+?)\s*<!-- icon: [A-Za-z0-9.]+ -->\s*$/ ? [$1, $2] : undef;
  # What is outside the HTML comments is the text: GitHub shows nothing of a comment.
  my ($line, $rest) = ("", $raw);
  while (length $rest) {
    if ($in_comment) { if ($rest =~ /-->(.*)$/s) { $rest = $1; $in_comment = 0; } else { $rest = ""; } }
    elsif ($rest =~ /^(.*?)<!--(.*)$/s) { $line .= $1; $rest = $2; $in_comment = 1; }
    else { $line .= $rest; $rest = ""; }
  }
  if ($heading) {
    my ($id, $t) = @$heading;
    fail("$guide:$gn: duplicate section id $id (first at line $line_of{$id})") if exists $text{$id};
    $text{$id} = "$t\n"; $title{$id} = $t; $line_of{$id} //= $gn; push @order, $id; $current = $id;
    next;
  }
  if ($line =~ /^## /) {
    fail("$guide:$gn: section without an id and an icon (## <a id=\"id\"></a>Title <!-- icon: symbol.name -->): $line");
    $current = undef; next;
  }
  next if $line =~ /^# /;
  $text{$current} .= "$line\n" if defined $current;
  while ($line =~ s/!\[[^\]]*\]\(([^)\s]*)[^)]*\)/ /) { push @images, [$gn, $1]; }
  while ($line =~ /\]\(([^)\s]*)[^)]*\)/g) { push @links, [$gn, $1]; }
}
close $g;

fail("$guide: the guide has no sections") unless @order;
for my $image (@images) {
  my ($n, $dest) = @$image;
  next if $dest =~ m{^images/[^:]+$} && $dest !~ m{(^|/)\.\.?(/|$)};
  fail("$guide:$n: an image must be a relative path into the docs images folder (images/...), not $dest");
}
for my $link (@links) {
  my ($n, $dest) = @$link;
  if ($dest =~ /^#(.+)$/) { fail("$guide:$n: link to a section that does not exist: #$1") unless exists $text{$1}; }
  elsif ($dest =~ m{^https://github\.com/k-electron/snapit(/|$)}) { }
  else { fail("$guide:$n: a link the guide may not have: $dest (only a section, #id, or https://github.com/k-electron/snapit)"); }
}

open(my $c, "<:encoding(UTF-8)", $checklist) or die "cannot read $checklist";
my ($lines, $cn) = (0, 0);
while (my $line = <$c>) {
  chomp $line; $cn++;
  next if $line =~ /^\s*(#|$)/;
  $lines++;
  my ($id, $terms) = split /\|/, $line, 2;
  unless (exists $text{$id}) { fail("$checklist:$cn: the checklist wants a section #$id, and the guide has none"); next; }
  for my $term (split /;/, $terms) {
    fail("$checklist:$cn: section #$id ($guide:$line_of{$id}) does not mention \"$term\"") unless index($text{$id}, $term) >= 0;
  }
}
close $c;
fail("$checklist: the checklist is empty") unless $lines;

# Every relative link in every Markdown file in the repo resolves.
my @docs;
find({
  no_chdir => 1,
  preprocess => sub { sort @_ },
  wanted => sub {
    my $path = $File::Find::name; $path =~ s{^\./}{};
    if (-d $path) {
      $File::Find::prune = 1 if $path =~ m{^(?:build|\.claude/worktrees|\.git)$} || $path =~ m{(?:^|/)target$};
      return;
    }
    push @docs, $path if $path =~ /\.md$/;
  },
}, ".");
my $links_checked = 0;
for my $doc (@docs) {
  open(my $d, "<:encoding(UTF-8)", $doc) or die "cannot read $doc";
  my ($fence_char, $fence_len, $n) = ("", 0, 0);
  while (my $line = <$d>) {
    chomp $line; $n++;
    if ($fence_len) {
      my ($run) = $line =~ /^ {0,3}(\Q$fence_char\E{3,})\s*$/;
      $fence_len = 0 if defined $run && length($run) >= $fence_len;
      next;
    }
    if ($line =~ /^ {0,3}(`{3,}|~{3,})/) { ($fence_char, $fence_len) = (substr($1, 0, 1), length $1); next; }
    (my $prose = $line) =~ s/(`+)(?:(?!\1).)+?\1/ /g;
    my @dests;
    while ($prose =~ /\]\(\s*(<[^>]*>|[^)\s]*)[^)]*\)/g) { push @dests, $1; }
    push @dests, $1 if $prose =~ /^ {0,3}\[[^\]]+\]:\s*(\S+)/;
    for my $dest (@dests) {
      $dest =~ s/^<|>$//g;
      next if $dest eq "" || $dest =~ /^#/ || $dest =~ m{^(?:[A-Za-z][A-Za-z0-9+.-]*:|//)};
      $links_checked++;
      (my $file = $dest) =~ s/[?#].*$//;
      $file =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
      my $target = $file =~ m{^/} ? ".$file" : dirname($doc) . "/$file";
      fail("$doc:$n: link to a file that does not exist: $dest") unless -e $target;
    }
  }
  close $d;
}

if ($failed) { exit 1; }
print "ok (" . scalar(@order) . " sections, $lines checked; " . scalar(@docs) . " Markdown files, $links_checked relative links)\n";
' docs/UserGuide.md scripts/user-guide-checklist.txt
