#!/usr/bin/env bash
# Checks the User Guide's source (snapit-editor/UserGuide/UserGuide.md) against the checklist of
# spec flows in scripts/user-guide-checklist.txt:
#   1. every section has a unique id, and a title;
#   2. every in-window link (`](#id)`) names a section that exists;
#   3. every checklist section exists and mentions every term of its line;
#   4. no image, no `http:` link, and no https link outside GitHub's (the guide is bundled and
#      fetches nothing).
# Flow 58 of the scripted run repeats 1 to 3 on the guide the helper actually loaded.
#
#   scripts/check-user-guide.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

exec perl -CSDA -e '
use strict; use warnings;
my ($guide, $checklist) = @ARGV;
my $failed = 0;
sub fail { print STDERR "error: $_[0]\n"; $failed = 1; }

open(my $g, "<:encoding(UTF-8)", $guide) or die "cannot read $guide";
my (%text, %title, @order, $current);
my @links;
while (my $line = <$g>) {
  chomp $line;
  if ($line =~ /^## (.+?)\s*\{#([a-z0-9-]+)(?:\s+icon=[A-Za-z0-9.]+)?\}\s*$/) {
    my ($t, $id) = ($1, $2);
    fail("duplicate section id $id") if exists $text{$id};
    $text{$id} = "$t\n"; $title{$id} = $t; push @order, $id; $current = $id;
    next;
  }
  if ($line =~ /^## /) { fail("section without an id: $line"); $current = undef; next; }
  next if $line =~ /^# /;
  $text{$current} .= "$line\n" if defined $current;
  while ($line =~ /\]\(([^)]*)\)/g) { push @links, $1; }
  fail("an image in the guide: $line") if $line =~ /!\[/;
}
close $g;

fail("the guide has no sections") unless @order;
for my $link (@links) {
  if ($link =~ /^#(.+)$/) { fail("link to a section that does not exist: #$1") unless exists $text{$1}; }
  elsif ($link =~ m{^https://github\.com/k-electron/snapit(/|$)}) { }
  else { fail("a link the guide may not have: $link"); }
}

open(my $c, "<:encoding(UTF-8)", $checklist) or die "cannot read $checklist";
my $lines = 0;
while (my $line = <$c>) {
  chomp $line;
  next if $line =~ /^\s*(#|$)/;
  $lines++;
  my ($id, $terms) = split /\|/, $line, 2;
  unless (exists $text{$id}) { fail("the checklist wants a section #$id, and the guide has none"); next; }
  for my $term (split /;/, $terms) {
    fail("section #$id does not mention \"$term\"") unless index($text{$id}, $term) >= 0;
  }
}
close $c;
fail("the checklist is empty") unless $lines;

if ($failed) { exit 1; }
print "ok (" . scalar(@order) . " sections, $lines checked)\n";
' snapit-editor/UserGuide/UserGuide.md scripts/user-guide-checklist.txt
