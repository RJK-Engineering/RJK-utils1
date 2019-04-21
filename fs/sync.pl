use strict;
use warnings;

use Options::Pod;

use File::Copy qw(move);
use File::Path qw(make_path);
use Number::Bytes::Human qw(format_bytes);

use RJK::Win32::Console;
use File::Traverse::Stats;
#~ use Wiki::Foswiki;

###############################################################################
=head1 DESCRIPTION

Find source files in target and move to correct dirs.

=head1 SYNOPSIS

sync.pl [options] [target directory]

=head1 DISPLAY EXTENDED HELP

sync.pl -h

=head1 OPTIONS

=for options start

=over 4

=item B<--foswiki-data-dir [path]>

Path to Fowsiki data directory.

=item B<--web [name]>

Web name. Default: Main

=item B<--dir-table [name]>

Directory table name. Default: Directory

=item B<--part-table [name]>

Partition table name. Default: Partition

=item B<--save>

Save table.

=item B<-i --refresh-interval [seconds]>

Refresh interval in seconds. Real number, default: 0.2

=item B<--mds --move-diff-size>

=item B<-v --verbose>

Be verbose.

=item B<-q --quiet>

Be quiet.

=item B<--debug>

Display debug information.

=back

=head2 Pod

=over 4

=item B<--podcheck>

Run podchecker.

=item B<--pod2html --html [path]>

Run pod2html. Writes to [path] if specified. Writes to
F<[path]/{scriptname}.html> if [path] is a directory.
E.g. C<--html .> writes to F<./{scriptname}.html>.

=item B<--genpod>

Generate POD for options.

=item B<--savepod>

Save generated POD to script file.
The POD text will be inserted between C<=for options start> and
C<=for options end> tags.
If no C<=for options end> tag is present, the POD text will be
inserted after the C<=for options start> tag and a
C<=for options end> tag will be added.
A backup is created.

=back

=head2 Help

=over 4

=item B<-h -? --help>

Display extended help.

=back

=for options end

=head1 USAGE

Type a drive letter to toggle between active/inactive.

=head2 Keys

[`]=Summary [1]=List [Tab]=Poke [F1]=[?]=Help [Esc]=Quit

=cut
###############################################################################

my %opts = (
    refreshInterval => .2,
    web => 'Main',
    dirDataTable => 'Directory',
    partDataTable => 'Partition',
    save => 0,
);
Options::Pod::GetOptions(
    ['Options'],
    'foswiki-data-dir=s' => \$opts{foswikiDataDir},
        "{Path} to Fowsiki data directory.",
    'web=s' => \$opts{web},
        "Web {name}. Default: $opts{web}",
    'dir-table=s' => \$opts{dirDataTable},
        "Directory table {name}. Default: $opts{dirDataTable}",
    'part-table=s' => \$opts{partDataTable},
        "Partition table {name}. Default: $opts{partDataTable}",

    'save' => \$opts{save}, "Save table.",
    'i|refresh-interval=f' => \$opts{refreshInterval},
        "Refresh interval in {seconds}. Real number, default: $opts{refreshInterval}",
    'mds|move-diff-size' => \$opts{moveDifferentSize}, "",

    'v|verbose' => \$opts{verbose}, "Be verbose.",
    'q|quiet' => \$opts{quiet}, "Be quiet.",
    'debug' => \$opts{debug}, "Display debug information.",

    ['Pod'],
    Options::Pod::Options,

    ['Help'],
    Options::Pod::HelpOptions
) || Options::Pod::pod2usage(
    -sections => "DISPLAY EXTENDED HELP",
);

@ARGV || Options::Pod::pod2usage(
    -sections => "DESCRIPTION|SYNOPSIS|DISPLAY EXTENDED HELP",
);

$opts{targetDir} = shift;
$opts{targetDir} =~ s|\/|\\|g;      # replace forward with backward slashes
$opts{targetDir} =~ s|\\+$||;   # remove trailing slashes
if (! -e $opts{targetDir}) {
    die "Target does not exist";
} elsif (! -d $opts{targetDir}) {
    die "Target is not a directory";
} elsif (! -r $opts{targetDir}) {
    die "Target dir is not readable";
}

###############################################################################

#~ UpdateWiki('E1', 'install', 'date');
#~ UpdateWiki('C', 'games', 'date');
#~ exit;

sub Ignore { 0 }

opendir my $dh, $opts{targetDir} || die "$!";
#~ chdir $opts{targetDir};
my @dirs = grep { -d "$opts{targetDir}\\$_" && ! /^\./ && ! Ignore($_) } readdir $dh;
closedir $dh;

my $filesInTarget; # filename => [ File ]
my $console = new RJK::Win32::Console();

my $stats;
sub DisplayTraverseStats {
    $console->updateLine(
        sprintf "%s in %s files",
            format_bytes($stats->size),
            $stats->files
    );
}

my $lastDisplay = 0;
my $traverse = new File::Traverse::Stats(
    visitFile => sub {
        my $file = shift;
        if ($lastDisplay < $stats->time - $opts{refreshInterval}) {
            DisplayTraverseStats();
            $lastDisplay = $stats->time;
        }
        push @{$filesInTarget->{$file->name}}, $file;
    },
);
$stats = $traverse->stats;

# index target
foreach (@dirs) {
    my $path = "$opts{targetDir}\\$_";
    $console->updateLine("Indexing $path ...\n");
    DisplayTraverseStats();
    $traverse->traverse($path);
}
DisplayTraverseStats();
$console->newline;

$traverse = new File::Traverse::Stats(
    visitFile => sub { VisitFile(@_) },
);
$stats = $traverse->stats;

# synchronize
foreach my $dir (@dirs) {
    print "Synchronizing $dir ...\n";

    if (! -e $dir) {
        print "Directory does not exist in source\n";
        next;
    } elsif (! -d $dir) {
        warn "Source is not a directory";
        exit;
    } elsif (! -r $dir) {
        warn "Source directory is not readable";
        exit;
    }

    $traverse->traverse($dir);
    DisplayTraverseStats();
    $console->newline();
}

#~ UpdateWiki('C', 'games', 'date');

sub UpdateWiki {
    my ($vol, $dir, $date) = @_;
    my $fw = new Wiki::Foswiki($opts{foswikiDataDir}, $opts{web});
    my $dt = $fw->getDataTable($opts{dirDataTable});
    my $row = $dt->getRow({
        Volume => $vol,
        Name => $dir,
    });
#~ use Data::Dumper;
#~ print Dumper($row);
    $row->set('Last Backup' => $date);
    #~ print $dt->{data}->csv;
#~ exit;
    $dt->save() if $opts{save};
    #~ $fw->saveDataTable($dt) if $opts{save};
}

# find source file in target and move to correct dir
sub VisitFile {
    my $source = shift;
    my $targetPath = "$opts{targetDir}\\$source->{path}";

    if (-e $targetPath) {
        return;
    }

    my $files = $filesInTarget->{$source->name};
    unless ($files) {
        print "File not found: $source->{name}\n" if $opts{verbose};
        return;
    }

    my @filesNew;
    if (@$files > 1) {
        printf "%u files with same name: %s\n",
            scalar @$files, $source->{name};

        my @sameSize;
        foreach (@$files) {
            # find same size
            if ($_->size == $source->size) {
                push @sameSize, $_;
            } else {
                push @filesNew, $_;
            }
        }

        if (@sameSize == 0) {
            print "File not found: $source->{name}\n" if $opts{verbose};
            return;
        } elsif (@sameSize > 1) {
            printf "%u files with same size: %s\n",
                scalar @sameSize, $source->{name};
            exit if $opts{exitOnDupes};
            return;
        }
        $files = \@sameSize;
    }

    my $target = $files->[0];
    if ($source->size != $target->size) {
        print "Same name, different size: $source->{name}\n";
        return unless $opts{moveDifferentSize};
    }

    printf "<%s\n", $target->path;
    my $targetDir = "$opts{targetDir}\\$source->{dir}";
    print ">$targetDir\n";

    if (! -e $targetDir) {
        make_path($targetDir) || die "Error creating directory";
    }
    -e $targetDir || die "Target directory does not exist";

    move($target->path, $targetDir) || die "Error moving file";
    sleep 1 if $opts{verbose};

    # remove from index
    if (@filesNew) {
        # new array with file to be moved removed
        $filesInTarget->{$source->name} = \@filesNew;
    } else {
        delete $filesInTarget->{$source->name};
    }
}
