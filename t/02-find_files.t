use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use NewsUP::Utils;
use 5.030;
use Data::Dumper;
use File::Spec::Functions;
use File::Path 'rmtree';
use Cwd;

my $OPTIONS = {
    TEMP_FOLDER          => catfile(getcwd(), 't/data/temp'),
    SPLITNPAR            => 0,
    SPLIT_CMD            => '7z a -mx0 -v50m --',
    SPLIT_PATTERN        => '*7z.*',
    OBFUSCATE            => 0,
    PAR2_PATH            => 'par2',
    PAR2_SETTINGS        => 'c -s768000 -r15',
    PAR2_RENAME_SETTINGS => 'c -s768000 -r0'
};

subtest 'find simple files' => sub {
    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES} = ['t/data/big_file.txt'];
    my $files             = find_files($OPTIONS);
    my @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 1);
    ok(@$files);
    is(scalar @$files, 1);
    is($files->[0], catfile($OPTIONS->{TEMP_FOLDER}, 'big_file.txt'));
    ok(-e $files->[0]);
    rmtree($OPTIONS->{TEMP_FOLDER});

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES} = ['t/data/big_file.txt', 't/data/empty.conf'];
    $files = find_files($OPTIONS);
    @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 2);
    ok(@$files);
    is(scalar @$files, 2);
    is((sort @$files)[0], catfile($OPTIONS->{TEMP_FOLDER}, 'big_file.txt'));
    ok(-f catfile($OPTIONS->{TEMP_FOLDER}, 'big_file.txt'));
    is((sort @$files)[1], catfile($OPTIONS->{TEMP_FOLDER}, 'empty.conf'));
    ok(-f catfile($OPTIONS->{TEMP_FOLDER}, 'empty.conf'));
    rmtree($OPTIONS->{TEMP_FOLDER});
    unlink(@$files);

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES}     = ['t/data/big_file.txt', 't/data/empty.conf'];
    $OPTIONS->{SPLITNPAR} = 1;
    my $files             = find_files($OPTIONS);
    my @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 2);
    ok(@$files == 2);
    rmtree($OPTIONS->{TEMP_FOLDER});
    unlink(@$files);

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES}     = ['t/data/big_file.txt'];
    $OPTIONS->{SPLITNPAR} = 1;
    $files                = find_files($OPTIONS);
    @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 2);
    ok(@$files == 2);
    rmtree($OPTIONS->{TEMP_FOLDER});
    unlink(@$files);

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES}     = ['t/data/big_file.txt', 't/data/empty.conf'];
    $OPTIONS->{SPLITNPAR} = 0;
    $OPTIONS->{OBFUSCATE} = 1;
    $files                = find_files($OPTIONS);
    @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 3);
    ok(@$files == 3);
    rmtree($OPTIONS->{TEMP_FOLDER});

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES}     = ['t/data/big_file.txt', 't/data/empty.conf'];
    $OPTIONS->{SPLITNPAR} = 1;
    $OPTIONS->{OBFUSCATE} = 1;
    $files                = find_files($OPTIONS);
    @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 8);
    ok(@$files == 8);
    rmtree($OPTIONS->{TEMP_FOLDER});
    unlink(@$files);

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{SPLITNPAR} = 0;
    $OPTIONS->{OBFUSCATE} = 0;
    $OPTIONS->{FILES}     = ['t/data/data_test_folder'];
    $files                = find_files($OPTIONS);
    @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 1);
    ok(@$files);
    is(scalar @$files, 4);
    ok(-e $_, 'File exist!') for (@$files);
    rmtree($OPTIONS->{TEMP_FOLDER});
    unlink(@$files);

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES} = ['t/data/big_file.txt', 't/data/data_test_folder'];
    $files = find_files($OPTIONS);
    @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 2);
    ok(@$files);
    is(scalar @$files, 5);
    ok(-e $_, 'File exist!') for (@$files);
    rmtree($OPTIONS->{TEMP_FOLDER});
    unlink(@$files);

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES}     = ['t/data/big_file.txt', 't/data/data_test_folder'];
    $OPTIONS->{SPLITNPAR} = 1;
    $files                = find_files($OPTIONS);
    @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 7);
    ok(@$files == 7);
    rmtree($OPTIONS->{TEMP_FOLDER});
    unlink(@$files);

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES}     = ['t/data/big_file.txt', 't/data/data_test_folder'];
    $OPTIONS->{SPLITNPAR} = 0;
    $OPTIONS->{OBFUSCATE} = 1;
    $files                = find_files($OPTIONS);
    @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 3);
    ok(@$files == 7);
    rmtree($OPTIONS->{TEMP_FOLDER});
    unlink(@$files);

    mkdir $OPTIONS->{TEMP_FOLDER};
    $OPTIONS->{FILES}     = ['t/data/big_file.txt', 't/data/data_test_folder'];
    $OPTIONS->{SPLITNPAR} = 1;
    $OPTIONS->{OBFUSCATE} = 1;
    $files                = find_files($OPTIONS);
    @existent_fs_files = glob(catfile($OPTIONS->{TEMP_FOLDER}, '*'));
    is(@existent_fs_files, 14);
    ok(@$files == 14);
    rmtree($OPTIONS->{TEMP_FOLDER});
    unlink(@$files);

};




done_testing();
