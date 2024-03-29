package Sync;

use File::Copy ();
use File::Path ();

use RJK::Files;
use RJK::Path;
use RJK::Paths;

use Display;
use IndexVisitor;

my $opts;
my $display;
my ($sourceDir, $targetDir);

sub execute {
    my $self = shift;
    $opts = shift;
    $display = new Display($opts);

    $sourceDir = $opts->{sourceDir} // ".";
    $targetDir = $opts->{targetDir};
    my $dirs = getDirs();
    my $left = createIndex($sourceDir, $dirs);
    my $right = createIndex($targetDir, $dirs, $left);

    $display->info("Synchronizing ...");
    if ($opts->{visitDirs}) {
        my $dirs = $left->dirs;
        foreach (sort keys %$dirs) {
            synchronizeDirs($dirs->{$_}, $right->dirs);
        }
    } else {
        my $files = $left->files;
        foreach (sort keys %$files) {
            synchronize($files->{$_}, $right->files);
        }
    }
}

sub getDirs {
    -e $targetDir or die "Target dir does not exist: $targetDir";
    -d $targetDir or die "Target is not a directory: $targetDir";
    -r $targetDir or die "Target dir is not readable: $targetDir";

    opendir my $dh, $targetDir or die "$!";
    my @dirs = grep { -d "$targetDir\\$_" && ! /^\./ } readdir $dh;
    closedir $dh;

    @dirs or die "No dirs in target dir: $targetDir";
    $display->info("Dir: $_") foreach @dirs;
    return \@dirs;
}

sub createIndex {
    my ($parent, $dirs, $left) = @_;

    my $stats = RJK::Files->createStats();
    $display->setStats($stats);
    my $visitor = new IndexVisitor($opts, $display, $parent, $left);

    foreach my $dir (@$dirs) {
        my $path = RJK::Paths->get($parent, $dir);
        $display->info("Reading $path ...");
        $display->stats;
        RJK::Files->traverse($path, $visitor, {}, $stats);
    }
    $display->totals;

    return $visitor;
}

sub synchronizeDirs {
    my ($dir, $right) = @_;
    my $nameMatch = $right->{$dir->{name}} or return;

    if (@$nameMatch > 1) {
        $display->info("Multimatch for name: $dir->{name}");
        return;
    }
    if ($dir->{path} eq $nameMatch->[0]) {
        $display->info("=$dir->{path}");
        return;
    }
    moveDir($dir, $nameMatch->[0], $right);
}

sub moveDir {
    my ($inSource, $inTarget, $right) = @_;
    my $newPath = $inSource->{path};
    my $newFullPath = RJK::Paths->get($targetDir, $newPath);

    $display->info("<$inTarget->{fullPath}");
    $display->info(">$newFullPath");

    my $newParent = RJK::Paths->get($targetDir, $inSource->{parent});
    move($inTarget->{fullPath}, $newParent, $newFullPath) unless $opts->{simulate};
    updateIndex($inTarget, $newFullPath, $newPath, $right);
}

sub updateIndex {
    my ($parent, $newParentFullPath, $newParentPath, $right) = @_;
    my $parentFullPath = quotemeta $parent->{fullPath};
    my $parentPath = quotemeta $parent->{path};
    foreach my $dirs (values %$right) {
        foreach my $dir (@$dirs) {
            $dir->{fullPath} =~ s/^$parentFullPath\\(.+)/$newParentFullPath\\$1/ or next;
            $dir->{parent} =~ s/^$parentPath/$newParentPath/ or die;
            $dir->{path} = RJK::Paths->get($dir->{parent}, $dir->{name});
        }
    }
}

sub move {
    my ($source, $destinationDir, $destination) = @_;
    if (! -e $destinationDir) {
        File::Path::make_path("$destinationDir") or die "$!: $destinationDir";
    }
    File::Copy::move("$source", "$destination") or die "$!: $source -> $destination";
}

sub synchronize {
    my ($file, $right) = @_;
    my $sizeMatch = $right->{$file->{size}} or return;

    my $match;
    foreach (@$sizeMatch) {
        if ($match) {
            $display->info("Multimatch for size: $file->{size}");
            return;
        }
        $match = $_ if sameDate($file, $_);
    }
    $match or return;

    if ($file->{parent} eq $match->{parent})  {
        renameFile($file, $match);
    } else {
        moveFile($file, $match);
    }
}

sub renameFile {
    my ($inSource, $inTarget) = @_;
    my $targetFile = RJK::Paths->get($targetDir, $inTarget->{parent}, $inSource->{name});

    $display->info("-$inTarget->{fullPath}");
    $display->info("+$targetFile");
    return if $opts->{simulate};

    File::Copy::move($inTarget->{fullPath}, "$targetFile") or die "$!: $inTarget -> $targetFile";
}

sub moveFile {
    my ($inSource, $inTarget) = @_;
    my $target = my $dir = RJK::Paths->get($targetDir, $inSource->{parent});

    $display->info("<$inTarget->{fullPath}");
    if ($inSource->{name} eq $inTarget->{name})  {
        $display->info(">$target\\");
    } else {
        $target = RJK::Paths->get($dir, $inSource->{name});
        $display->info(">$target");
    }
    return if $opts->{simulate};

    move($inTarget->{fullPath}, $dir, $target);
}

sub sameDate {
    my ($inSource, $inTarget) = @_;
    if ($opts->{useFatDateResolution}) {
        return abs($inSource->{modified} - $inTarget->{modified}) < 3;
    } else {
        return $inSource->{modified} == $inTarget->{modified};
    }
}

1;
