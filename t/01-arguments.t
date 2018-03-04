use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use NewsUP::Utils;
use 5.026;
use Data::Dumper;

subtest 'Read config file check and defaults' => sub {
    $NewsUP::Utils::CONFIGURATION_FILE = './t/data/newsup.conf';
    my %OPTIONS = %{read_options()};
    ok($OPTIONS{UPLOAD_SIZE} == 768000,                       'Read Config File UPLOAD_SIZE');
    ok($OPTIONS{OBFUSCATE} == 0,                              'Read Config File OBFUSCATE');
    ok(@{$OPTIONS{GROUPS}} == 1,                              'Read Config File GROUPS size');
    ok($OPTIONS{GROUPS}->[0] eq 'alt.binaries.test',          'Read Config File GROUPS value');
    ok($OPTIONS{AUTH_USER} eq 'myLogin',                      'Read Config File AUTH_USER');
    ok($OPTIONS{AUTH_PASS} eq 'myPassword',                   'Read Config File AUTH_PASS');
    ok($OPTIONS{CONNECTIONS} == 6,                            'Read Config File CONNECTIONS');
    ok($OPTIONS{SERVER} eq 'nntp.server.com',                 'Read Config File SERVER');
    ok($OPTIONS{SERVER_PORT} == 443,                          'Read Config File SERVER_PORT');
    ok($OPTIONS{TLS} == 1,                                    'Read Config File TLS');
    ok($OPTIONS{TLS_IGNORE_CERTIFICATE} == 0,                 'Read Config File TLS_IGNORE_CERTIFICATE');
    ok($OPTIONS{HEADERCHECK} == 1,                            'Read Config File HEADERCHECK');
    ok($OPTIONS{HEADERCHECK_SERVER} eq 'nntp.server2.com',    'Read Config File HEADERCHECK_SERVER');
    ok($OPTIONS{HEADERCHECK_SERVER_PORT} == 119,              'Read Config File HEADERCHECK_SERVER_PORT');
    ok($OPTIONS{HEADERCHECK_CONNECTIONS} == 3,                'Read Config File HEADERCHECK_CONNECTIONS');
    ok($OPTIONS{HEADERCHECK_AUTH_USER} eq 'myUser',           'Read Config File HEADERCHECK_AUTH_USER');
    ok($OPTIONS{HEADERCHECK_AUTH_PASS} eq 'myPassword',       'Read Config File HEADERCHECK_AUTH_PASS');
    ok($OPTIONS{HEADERCHECK_RETRIES} == 3,                    'Read Config File HEADERCHECK_RETRIES');
    ok($OPTIONS{HEADERCHECK_SLEEP} == 20,                     'Read Config File HEADERCHECK_SLEEP');
    ok($OPTIONS{UPLOADER} eq 'NewsUP <NewsUP@somewhere.cbr>', 'Read Config File UPLOADER');
    ok(keys %{$OPTIONS{METADATA}} == 2,                       'Read Config File METADATA size');
    ok(exists $OPTIONS{METADATA}->{client},                   'Read Config File METADATA key');
    ok($OPTIONS{METADATA}->{client} eq 'NewsUP',              'Read Config File METADATA value');
    ok($OPTIONS{SPLITNPAR} == 1,                              'Read Config File SPLITNPAR');
    ok($OPTIONS{PAR2} == 1,                                   'Read Config File PAR2');
    ok($OPTIONS{PAR2_RENAME_SETTINGS} eq 'c -s768000 -r0',    'Read Config File PAR2_RENAME_SETTINGS');
    ok(keys %{$OPTIONS{HEADERS}} == 4,                        'Read Config File HEADERS size');
    ok(exists $OPTIONS{HEADERS}->{'extra-header'},            'Read Config File HEADERS key 1');
    ok($OPTIONS{HEADERS}->{'extra-header'} eq 'value1',       'Read Config File HEADERS value 1');
    ok(exists $OPTIONS{HEADERS}->{'extra-header2'},           'Read Config File HEADERS key 2');
    ok($OPTIONS{HEADERS}->{'extra-header2'} eq 'value2',      'Read Config File HEADERS value 2');
    ok($OPTIONS{UPLOAD_NZB} == 1,                             'Read Config File UPLOAD_NZB');
    ok($OPTIONS{NZB_SAVE_PATH} eq '/data/uploads/',           'Read Config File UPLOAD_NZB');
};


subtest 'Command line' => sub {
    $NewsUP::Utils::CONFIGURATION_FILE = undef;
    local @ARGV = (
        '--file',           'my_file_to_upload', '--list',             'my_file_with_files',
        '--uploadSize',     800000,              '--obfuscate',        '--group',
        'this.a.newsgroup', '--group',           'this.another.group', '--metadata',
        'key1=value1',      '--metadata',        'key2=value2',        '--port',
        563,                '--unzb',            '--comment',          'comment 1',
        '--comment',        'comment 2'
    );
    my %OPTIONS = %{read_options()};
    ok(@{$OPTIONS{FILES}} == 1,                       'Command line FILES size');
    ok($OPTIONS{FILES}->[0] eq 'my_file_to_upload',   'Command line FILES value');
    ok($OPTIONS{UPLOAD_SIZE} == 800000,               'Command line UPLOAD_SIZE');
    ok($OPTIONS{OBFUSCATE} == 1,                      'Command line OBFUSCATE');
    ok(@{$OPTIONS{GROUPS}} == 2,                      'Command line GROUPS size');
    ok($OPTIONS{GROUPS}->[0] eq 'this.a.newsgroup',   'Command line GROUPS value 1');
    ok($OPTIONS{GROUPS}->[1] eq 'this.another.group', 'Command line GROUPS value 2');
    ok($OPTIONS{SERVER_PORT} == 563,                  'Command line SERVER_PORT');
    ok($OPTIONS{UPLOAD_NZB},                          'Command line UPLOAD_NZB');
    ok(@{$OPTIONS{COMMENTS}} == 2,                    'Command line GROUPS size');
    ok($OPTIONS{COMMENTS}->[0] eq 'comment 1',        'Command line GROUPS value 1');
    ok($OPTIONS{COMMENTS}->[1] eq 'comment 2',        'Command line GROUPS value 2');
};

subtest 'Defaults' => sub {
    $NewsUP::Utils::CONFIGURATION_FILE = './t/data/empty.conf';
    my %OPTIONS = %{read_options()};
    ok($OPTIONS{UPLOAD_SIZE} == 768000,                    'Default UPLOAD_SIZE');
    ok($OPTIONS{OBFUSCATE} == 0,                           'Default OBFUSCATE');
    ok(@{$OPTIONS{GROUPS}} == 0,                           'Default GROUPS');
    ok($OPTIONS{SERVER_PORT} == 443,                       'Default SERVER_PORT');
    ok($OPTIONS{TLS} == 1,                                 'Default TLS');
    ok($OPTIONS{TLS_IGNORE_CERTIFICATE} == 0,              'Default TLS_IGNORE_CERTIFICATE');
    ok($OPTIONS{HEADERCHECK_CONNECTIONS} == 1,             'Default HEADERCHECK_CONNECTIONS');
    ok($OPTIONS{RARNPAR} == 0,                             'Default RARNPAR');
    ok($OPTIONS{SPLIT_SIZE} == 10,                         'Default SPLIT_SIZE');
    ok($OPTIONS{PAR2} == 0,                                'Default PAR2');
    ok($OPTIONS{PAR2_RENAME_SETTINGS} eq 'c -s768000 -r0', 'Read Config File PAR2_RENAME_SETTINGS');
    ok($OPTIONS{SFV} == 0,                                 'Default SFV');
    ok($OPTIONS{REPAIR} == 0,                              'Default REPAIR');
    ok($OPTIONS{UPLOAD_NZB} == 0,                          'Default UPLOAD_NZB');
    ok($OPTIONS{DAEMON} == 0,                              'Default DAEMON');


};



done_testing;
