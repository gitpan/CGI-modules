use ExtUtils::MakeMaker;
WriteMakefile(
	NAME => "CGI",
	DISTNAME => "CGI-modules",
	VERSION => "2.76",
        linkext => { LINKTYPE => '' },
        dist => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'},
);
