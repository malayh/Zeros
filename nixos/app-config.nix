{ config, pkgs, lib, ... }:

{
  networking.extraHosts = ''
    127.0.0.1 minio
  '';
}
