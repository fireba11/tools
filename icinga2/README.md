Customized icinga2 scripts
* mail-*-notification.sh: reasonably pretty HTML notifications based on default scripts
* check_ad_replication.ps1: patched https://exchange.nagios.org/directory/Plugins/Operating-Systems/Windows/AD-Replication-Check-%28with-performance-counters-from-DRA%29/details because it didn't work on *one* of my domain controllers because the counter Paths were different
* check_scalelite: for https://github.com/blindsidenetworks/scalelite to verify the cluster got enough nodes