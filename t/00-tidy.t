use Test::More;

is(system('./t/data/tidy.sh'), 0, "tidy");

done_testing();
