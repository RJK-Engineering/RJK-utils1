use strict;
use warnings;

use File::Copy qw(move);
use File::stat;
use Time::localtime;
use Options::Pod;
use Media::Info::FFmpeg;

###############################################################################
=head1 DESCRIPTION

Move files to subdir of current working dir based on properties.

File properties: dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks

Detail properties for atime, mtime and ctime: sec min hour mday mon year wday yday isdst

Format example: "{mtime.year}{mtime.mon}{mtime.mday}"

Default format: "{mtime.year}"

=head1 SYNOPSIS

move.pl [list file] [format]

=head1 DISPLAY EXTENDED HELP

chdir.pl -h

=for options start

=head1 OPTIONS

=over 4

=item B<-d -dry-run>

Don't actually move files.

=item B<-e -exit-status [integer]>

Exit status on successful execution.

=item B<-q -quiet>

Be quiet.

=back

=head1 HELP

=over 4

=item B<-h -help -?>

Display extended help.

=back

=head1 POD

=over 4

=item B<-podcheck>

Run podchecker.

=item B<-pod2html -html [path]>

Run pod2html. Writes to [path] if specified. Writes to
F<[path]/{scriptname}.html> if [path] is a directory.
E.g. C<--html .> writes to F<./{scriptname}.html>.

=item B<-genpod>

Generate POD for options.

=item B<-writepod>

Write generated POD to script file.
The POD text will be inserted between C<=for options start> and
C<=for options end> tags.
If no C<=for options end> tag is present, the POD text will be
inserted after the C<=for options start> tag and a
C<=for options end> tag will be added.
A backup is created.

=back

=for options end

=cut
###############################################################################

my %opts = (exitStatus => 0);
Options::Pod::GetOptions(
    ['OPTIONS'],
    'd|dry-run' => \$opts{dryRun}, "Don't actually move files.",
    'e|exit-status=i' => \$opts{exitStatus}, "Exit status on successful execution.",
    'q|quiet' => \$opts{quiet}, "Be quiet.",
    ['HELP'],
    Options::Pod::HelpOptions("DESCRIPTION|SYNOPSIS|OPTIONS|HELP|POD"),
    ['POD'],
    Options::Pod::Options
);

@ARGV || Options::Pod::pod2usage(
    -sections => "DESCRIPTION|SYNOPSIS|DISPLAY EXTENDED HELP"
);

###############################################################################

my ($filelist, $dirFormat) = @ARGV;
defined $filelist or die "No filelist";
-T $filelist or die "Not a text file: $filelist";

my $prop = "atime";
$dirFormat //= "{mtime.year}";
#~ my $dirFormat //= "{mtime.year}{mtime.mon}{mtime.mday}";

open my $fh, '<', $filelist or die "$!: $filelist";
while (<$fh>) {
    chomp;
    next if !-f;
    my $file = $_;
    my $st = stat $file or die "$!: $file";

    my $dirName = $dirFormat;
    $dirName =~ s/\{(\w+)\.?(\w+)?\}/
        my $major = $1;
        my $minor = $2;
        if ($major eq 'video') {
            return if ! $minor;
            my $mi = Media::Info::FFmpeg->info($file);
            $mi &&
            $mi->{video} &&
            $mi->{video}[0] &&
            defined $mi->{video}[0]{$minor} ? $mi->{video}[0]{$minor} : "";
        } elsif ($major eq 'audio') {
            return if ! $minor;
            my $mi = Media::Info::FFmpeg->info($file);
            $mi &&
            $mi->{audio} &&
            $mi->{audio}[0] &&
            defined $mi->{audio}[0]{$minor} ? $mi->{audio}[0]{$minor} : "";
        } elsif ($minor) {
            my $t = localtime $st->$major;
            my $v = $t->$minor;
            $v += 1900 if $minor eq 'year';
            $v = sprintf("%02u", $v+1) if $minor eq 'mon';
            $v = sprintf("%02u", $v) if $minor eq 'mday';
            $v;
        } else {
            $st->$major;
        }
    /ge; #/

    next if ! $dirName && $dirName ne '0';

    print "$dirName $file\n" unless $opts{quiet};
    next if $opts{dryRun};
    mkdir $dirName;
    move $file, $dirName or die "$!: $file";
}

exit $opts{exitStatus};
