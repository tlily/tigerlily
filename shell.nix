{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    nativeBuildInputs = with pkgs.buildPackages; [ 
	perl
	perlPackages.Curses
	perlPackages.CGI
	perlPackages.IOSocketSSL
    ];
}
