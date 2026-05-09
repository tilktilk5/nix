{ pkgs, ... }:

{
  home.packages = with pkgs; [
	lynx    
	vivaldi
        vivaldi-ffmpeg-codecs
        google-chrome
        qutebrowser
  ];
}
