#!/usr/bin/env bash
# The docs check. It has two kinds of rules.
#
# The User Guide's one source (docs/UserGuide.md, bundled into the Editor helper and read on
# GitHub), against the checklist of spec flows in scripts/user-guide-checklist.txt. A section
# is exactly `## <a id="id"></a>Title <!-- icon: symbol.name -->` (an id of a-z, 0-9 and "-", one space
# before the comment, none after it; GuideDocument.swift reads the same form, and
# `scripts/check-docs.sh --sections` prints the `id|icon` of every section for flow 58). HTML comments,
# on one line or several, are not text. Every failure names the file and the line:
#   1. every section has an id and an icon in that form, and each id is unique;
#   2. every in-window link (`](#id)`) names a section that exists;
#   3. every checklist section exists and mentions every term of its line;
#   4. a link goes to a section or to https://github.com/k-electron/snapit, nowhere else (the
#      guide is bundled and fetches nothing);
#   5. an image is a Markdown image of a line of its own, a relative path into the docs images folder
#      (`images/...`, from the guide), and the guide holds no HTML img, picture or source (the
#      window shows raw HTML as text).
# Flow 58 of the scripted run repeats 1 to 3 on the guide the helper actually loaded.
#
# Every Markdown file in the repo (build output, Cargo's target folder, .git and the agent
# worktrees excepted). Code spans and fenced code are skipped; so is what an HTML comment holds,
# for images. A destination with a scheme (https:, mailto:, data:) or to a place in the same page
# (#id) is not a file and is not looked up. Every failure is file:line.
#   6. every relative link (a Markdown link, or the href of an HTML a, area or link) resolves to a
#      file or folder that exists;
#   7. every image (a Markdown image, an HTML img src, a source srcset with each of its
#      candidates) is a file that exists;
#   8. the shot list (docs/development/shot-list.md) has one `### <id>` heading per shot, a
#      lowercase-kebab id, with a `File:` line naming <user-guide|readme>/<id>.png (.gif);
#   9. every file under docs/images/ is in the shot list (a path matches its File line; Finder
#      .DS_Store files are ignored; the folder need not exist);
#  10. every slot marker (<!-- shot: id -->) names a shot in the shot list. A marker whose file is
#      not there yet is pending: printed as a count and a list, and never a failure.
#
#   scripts/check-docs.sh
#   scripts/check-docs.sh --sections   # the `id|icon` of each guide section, in order, for flow 58
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

exec perl -CSDA -e '
use strict; use warnings;
use File::Find; use File::Basename qw(dirname);
my ($mode, $guide, $checklist) = @ARGV;
my $failed = 0;
sub fail { print STDERR "error: $_[0]\n"; $failed = 1; }

open(my $g, "<:encoding(UTF-8)", $guide) or die "cannot read $guide";
my (%text, %title, %icon, %line_of, @order, $current, $in_comment);
my (@links, @images);   # [line, destination]
my $gn = 0;
while (my $raw = <$g>) {
  chomp $raw; $gn++;
  my $heading = !$in_comment && $raw =~ /^## <a id="([a-z0-9-]+)"><\/a>(\S(?:.*?\S)?) <!-- icon: ([A-Za-z0-9.]+) -->$/ ? [$1, $2, $3] : undef;
  # What is outside the HTML comments is the text: GitHub shows nothing of a comment.
  my ($line, $rest) = ("", $raw);
  while (length $rest) {
    if ($in_comment) { if ($rest =~ /-->(.*)$/s) { $rest = $1; $in_comment = 0; } else { $rest = ""; } }
    elsif ($rest =~ /^(.*?)<!--(.*)$/s) { $line .= $1; $rest = $2; $in_comment = 1; }
    else { $line .= $rest; $rest = ""; }
  }
  if ($heading) {
    my ($id, $t, $icon) = @$heading;
    if (exists $text{$id}) {   # the first section keeps its text; the lines of this one are not read into it
      fail("$guide:$gn: duplicate section id $id (first at line $line_of{$id})");
      $current = undef; next;
    }
    $text{$id} = "$t\n"; $title{$id} = $t; $icon{$id} = $icon; $line_of{$id} = $gn; push @order, $id; $current = $id;
    next;
  }
  if ($line =~ /^## /) {
    fail("$guide:$gn: a section is exactly ## <a id=\"id\"></a>Title <!-- icon: symbol.name --> (id of a-z, 0-9 and -, one space before the comment, nothing after it): $line");
    $current = undef; next;
  }
  next if $line =~ /^# /;
  $text{$current} .= "$line\n" if defined $current;
  # The window draws no raw HTML image, and an image is a line of its own.
  (my $prose = $line) =~ s/(`+)(?:(?!\1).)+?\1/ /g;
  fail("$guide:$gn: the guide has no HTML <$1> (the window would show it as text); an image is ![alt](images/...) on a line of its own") if $prose =~ /<\s*\/?\s*(img|picture|source)\b/i;
  fail("$guide:$gn: an image is on a line of its own (![alt](images/...), alone, or alone inside one link): $line")
    if $prose =~ /!\[[^\]]*\]\(/ && $prose !~ /^\s*(?:\[\s*)?(?:!\[[^\]]*\]\([^)]*\)\s*)+(?:\]\([^)]*\))?\s*$/;
  while ($line =~ s/!\[[^\]]*\]\(([^)\s]*)[^)]*\)/ /) { push @images, [$gn, $1]; }
  while ($line =~ /\]\(([^)\s]*)[^)]*\)/g) { push @links, [$gn, $1]; }
}
close $g;

if ($mode eq "--sections") { print "$_|$icon{$_}\n" for @order; exit($failed ? 1 : 0); }
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

# Every Markdown file in the repo: links, images and slot markers.
my ($SHOTLIST, $IMAGES) = ("docs/development/shot-list.md", "docs/images");
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

# The file a relative destination names, or undef when it is not a file (a place in the same page,
# or a scheme: https:, mailto:, data:).
sub target_of {
  my ($doc, $dest) = @_;
  $dest =~ s/^<|>$//g;
  return undef if $dest eq "" || $dest =~ /^#/ || $dest =~ m{^(?:[A-Za-z][A-Za-z0-9+.-]*:|//)};
  (my $file = $dest) =~ s/[?#].*$//;
  $file =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
  return $file =~ m{^/} ? ".$file" : dirname($doc) . "/$file";
}
sub line_at { my ($text, $offset) = @_; return 1 + (substr($text, 0, $offset) =~ tr/\n//); }

my ($links_checked, $images_checked) = (0, 0);
my (@slots, %shot_file, %shot_line);   # slots: [doc, line, id]; shots: id => path under the images folder
for my $doc (@docs) {
  open(my $d, "<:encoding(UTF-8)", $doc) or die "cannot read $doc";
  # Prose is each line without fenced code and code spans; a fence or a span is not a link, an image or a slot.
  my (@raw, @prose, @fenced);
  my ($fence_char, $fence_len) = ("", 0);
  while (my $line = <$d>) {
    chomp $line; push @raw, $line;
    if ($fence_len) {
      my ($run) = $line =~ /^ {0,3}(\Q$fence_char\E{3,})\s*$/;
      $fence_len = 0 if defined $run && length($run) >= $fence_len;
      push @prose, ""; push @fenced, 1; next;
    }
    if ($line =~ /^ {0,3}(`{3,}|~{3,})/) { ($fence_char, $fence_len) = (substr($1, 0, 1), length $1); push @prose, ""; push @fenced, 1; next; }
    (my $p = $line) =~ s/(`+)(?:(?!\1).)+?\1/ /g;
    push @prose, $p; push @fenced, 0;
  }
  close $d;
  my $flat = join("\n", @prose);

  # Slot markers: <!-- shot: id -->.
  while ($flat =~ /<!--\s*shot:\s*(.*?)\s*-->/gis) { push @slots, [$doc, line_at($flat, $-[0]), $1]; }

  # What a comment holds is not shown: images and links are looked up outside the comments.
  (my $shown = $flat) =~ s{<!--(.*?)-->}{"\n" x ($1 =~ tr/\n//)}gse;

  # An image is a Markdown image, an HTML img src, or a source srcset (a list of candidates).
  my @refs;   # [offset, destination]
  while ($shown =~ /!\[[^\]]*\]\(\s*(<[^>]*>|[^)\s]*)[^)]*\)/g) { push @refs, [$-[1], $1]; }
  while ($shown =~ /<(?:img|source)\b([^>]*)>/gis) {
    my ($attrs, $base) = ($1, $-[1]);
    while ($attrs =~ /\b(src|srcset)\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))/gi) {
      my ($name, $value, $at) = (lc $1, $2 // $3 // $4, $-[0]);
      my @candidates = $name eq "srcset" ? split(/,/, $value) : ($value);
      for my $candidate (@candidates) {
        $candidate =~ s/^\s+//;
        my ($url) = split /\s+/, $candidate;
        push @refs, [$base + $at, $url] if defined $url && length $url;
      }
    }
  }
  for my $ref (sort { $a->[0] <=> $b->[0] } @refs) {
    my ($offset, $dest) = @$ref;
    my $target = target_of($doc, $dest) // next;
    $images_checked++;
    fail("$doc:" . line_at($shown, $offset) . ": image of a file that does not exist: $dest") unless -e $target;
  }

  # An HTML href (a, area, link) is a link like a Markdown one.
  while ($shown =~ /<(?:a|area|link)\b([^>]*)>/gis) {
    my $attrs = $1; my $base = $-[1];
    next unless $attrs =~ /\bhref\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))/i;
    my ($dest, $at) = ($1 // $2 // $3, $-[0]);
    my $target = target_of($doc, $dest) // next;
    $links_checked++;
    fail("$doc:" . line_at($shown, $base + $at) . ": link to a file that does not exist: $dest") unless -e $target;
  }

  # Links: a link is not an image, so images are taken out first.
  my $n = 0;
  for my $p (@prose) {
    $n++;
    (my $text = $p) =~ s/!\[[^\]]*\]\(\s*(?:<[^>]*>|[^)\s]*)[^)]*\)/ /g;
    my @dests;
    while ($text =~ /\]\(\s*(<[^>]*>|[^)\s]*)[^)]*\)/g) { push @dests, $1; }
    push @dests, $1 if $text =~ /^ {0,3}\[[^\]]+\]:\s*(\S+)/;
    for my $dest (@dests) {
      my $target = target_of($doc, $dest) // next;
      $links_checked++;
      fail("$doc:$n: link to a file that does not exist: $dest") unless -e $target;
    }
  }

  # The shot list: one `### id` heading per shot, with a `File:` line naming a path under the images folder.
  if ($doc eq $SHOTLIST) {
    my $id;
    for my $i (0 .. $#raw) {
      my ($n, $line, $p) = ($i + 1, $raw[$i], $prose[$i]);
      next if $fenced[$i];
      if ($p =~ /^#{1,6}\s/) {
        $id = undef;
        next unless $p =~ /^### (.*?)\s*$/;
        my $title = $1;
        unless ($title =~ /^[a-z0-9]+(?:-[a-z0-9]+)*$/) { fail("$doc:$n: a shot heading is a lowercase-kebab id (### menu-bar-menu), not: $title"); next; }
        fail("$doc:$n: duplicate shot id $title (first at line $shot_line{$title})") if exists $shot_line{$title};
        $shot_line{$title} //= $n; $id = $title; next;
      }
      next unless defined $id && $line =~ /^\s*(?:[-*]\s+)?File:\s*`?([^`\s]*)`?\s*$/;
      my $file = $1;
      unless ($file =~ m{^(?:user-guide|readme)/\Q$id\E\.(?:png|gif)$}) { fail("$doc:$n: the file of shot $id is user-guide/$id.png or readme/$id.png (.gif for an animation), not: $file"); $shot_file{$id} = $file; next; }
      fail("$doc:$n: shot $id has two File lines") if exists $shot_file{$id};
      $shot_file{$id} = $file;
    }
    for my $s (sort keys %shot_line) { fail("$doc:$shot_line{$s}: shot $s has no File line (- File: `user-guide/$s.png`)") unless exists $shot_file{$s}; }
  }
}
fail("$SHOTLIST: the shot list does not exist") unless grep { $_ eq $SHOTLIST } @docs;

# Every file in the images folders is in the shot list. A shot is added by putting its file in place.
my %listed = map { ("$IMAGES/$_" => 1) } values %shot_file;
my $images_found = 0;
if (-d $IMAGES) {
  find({ no_chdir => 1, preprocess => sub { sort @_ }, wanted => sub {
    my $path = $File::Find::name; $path =~ s{^\./}{};
    return if -d $path || $path =~ m{(?:^|/)\.DS_Store$};
    $images_found++;
    fail("$path: an image file that is not in the shot list ($SHOTLIST)") unless $listed{$path};
  } }, $IMAGES);
}

# Every slot marker names a shot in the shot list. One whose file is not there yet is pending.
my @pending;
for my $slot (@slots) {
  my ($doc, $n, $id) = @$slot;
  if (!exists $shot_file{$id}) { fail("$doc:$n: slot marker for a shot that is not in the shot list ($SHOTLIST): $id"); next; }
  push @pending, "$id ($doc:$n)" unless -e "$IMAGES/$shot_file{$id}";
}

if (@pending) {
  print scalar(@pending) . " pending shots (a slot marker with no file yet; they do not fail the check):\n";
  print "  $_\n" for @pending;
}
if ($failed) { exit 1; }
print "ok (" . scalar(@order) . " sections, $lines checked; " . scalar(@docs) . " Markdown files, $links_checked relative links, $images_checked images; "
  . scalar(keys %shot_file) . " shots, " . scalar(@slots) . " slots, " . scalar(@pending) . " pending)\n";
' -- "${1:-}" docs/UserGuide.md scripts/user-guide-checklist.txt
