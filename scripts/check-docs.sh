#!/usr/bin/env bash
# The docs check. It has two kinds of rules.
#
# The User Guide's source (snapit-editor/UserGuide/UserGuide.md), against the checklist of spec
# flows in scripts/user-guide-checklist.txt:
#   1. every section has a unique id, and a title;
#   2. every in-window link (`](#id)`) names a section that exists;
#   3. every checklist section exists and mentions every term of its line;
#   4. no image, no `http:` link, and no https link outside GitHub's (the guide is bundled and
#      fetches nothing).
# Flow 58 of the scripted run repeats 1 to 3 on the guide the helper actually loaded.
#
# Every Markdown file in the repo (build output, Cargo's target folder, .git and the agent
# worktrees excepted):
#   5. every relative link and image resolves to a file or folder that exists, reported as
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
' snapit-editor/UserGuide/UserGuide.md scripts/user-guide-checklist.txt
