package SyncFileVisitor;
use parent 'RJK::FileVisitor';

# find source file in target and move to correct dir

use strict;
use warnings;

use File::Copy ();
use File::Path ();

use RJK::Path;
use RJK::Paths;
use RJK::Stat;

sub new {
    my $self = bless {}, shift;
    $self->{filesInTarget} = shift;
    $self->{filesInSource} = {};
    $self->{opts} = shift;
    $self->{modified} = [];
    $self->{notInTarget} = [];
    return $self;
}

sub visitFile {
    my ($self, $source, $sourceStat) = @_;

    my $target = RJK::Paths->get($self->{opts}{targetDir}, $source->{directories}, $source->{name});

    if ($self->{filesInSource}{$source->{name}}) {
        warn "Skipping duplicate: $source->{name}";
        return;
    }
    $self->{filesInSource}{$source->{name}} = 1;

    if (-e $target->{path}) {
        $self->checkTarget($sourceStat, $target->{path});
        return;
    }

    my $inTarget = $self->findMoved($source->{name}, $sourceStat)
        || $self->findRenamed($sourceStat);

    if (! $inTarget) {
        push @{$self->{notInTarget}}, $source;
        return;
    }

    if ($self->{opts}{moveFilesInTarget}) {
        $self->moveFile($inTarget, $target, $source->{name});
        $self->removeFromIndex($source, $sourceStat, $inTarget);
    }
}

sub checkTarget {
    my ($self, $sourceStat, $targetPath) = @_;
    my $targetStat = RJK::Stat->get($targetPath);
    if ($sourceStat->size != $targetStat->size) {
        warn "Size mismatch, " . $sourceStat->size . " != " . $targetStat->size . ": $targetPath";
        push @{$self->{modified}}, $targetPath;
    }
    if (! $self->checkDates($sourceStat, $targetStat)) {
        warn "Date mismatch: $targetPath";
        push @{$self->{modified}}, $targetPath;
    }
}

sub checkDates {
    my ($self, $sourceStat, $targetStat) = @_;
    return abs($sourceStat->modified - $targetStat->modified) < 3;
}

# files in diffent directory (same name, size and modified date)
sub findMoved {
    my ($self, $name, $sourceStat) = @_;
    my $inTarget = $self->{filesInTarget}{name}{$name};

    if (! $inTarget) {
        return;
    }

    if (@$inTarget > 1) {
        printf "%u files with same name: %s\n",
            scalar @$inTarget, $name;
    }

    my @same;
    foreach my $target (@$inTarget) {
        if ($sourceStat->size != $target->{stat}{size}) {
            print "Same name, different size: $target->{path}\n";
        } elsif (! $self->checkDates($sourceStat, $target->{stat})) {
            print "Same name, same size, diffent dates: $target->{path}\n";
        } else {
            push @same, $target;
        }
    }

    if (@same > 1) {
        printf "%u duplicate files: %s\n",
            scalar @same, join(" ", map { $_->{path} } @same);
        return;
    }

    return shift @same;
}

# files with same size and modified date (can be in different directory)
sub findRenamed {
    my ($self, $sourceStat) = @_;
    my $inTarget = $self->{filesInTarget}{size}{$sourceStat->size};

    if (! $inTarget) {
        return;
    }

    if (@$inTarget > 1) {
        printf "%u files with same size: %u\n",
            scalar @$inTarget, $sourceStat->size;
    }

    my @same;
    foreach my $target (@$inTarget) {
        if ($self->checkDates($sourceStat, $target->{stat})) {
            push @same, $target;
        }
    }

    if (@same > 1) {
        printf "%u files with same size and dates: %s\n",
            scalar @same, join(" ", map { $_->{path} } @same);
        return;
    }

    return shift @same;
}

sub moveFile {
    my ($self, $inTarget, $target, $sourceName) = @_;

    my $parent = $target->parent;
    if ($self->{opts}{dryRun}) {
        -e $parent or print "Target directory does not exist: $parent\n";
    } else {
        if (! -e $parent) {
            File::Path::make_path($parent) or die "$!: $parent";
        }
        -e $parent or die "Target directory does not exist: $parent";
    }

    my $targetPath = $sourceName eq $inTarget->{name} ? $parent : $target->{path};

    print "<$inTarget->{path}\n";
    print ">$targetPath\n";
    if (! $self->{opts}{dryRun}) {
        File::Copy::move($inTarget->{path}, $targetPath) or die "$!: $inTarget->{path} -> $targetPath";
    }

    sleep 1 if $self->{opts}{verbose};
}

sub removeFromIndex {
    my ($self, $source, $sourceStat, $inTarget) = @_;

    my $it = $self->{filesInTarget}{name}{$source->{name}};
    @$it = grep { $_ != $inTarget } @$it;

    $it = $self->{filesInTarget}{size}{$sourceStat->size};
    @$it = grep { $_ != $inTarget } @$it;
}

1;
