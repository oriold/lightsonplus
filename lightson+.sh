#!/usr/bin/env bash
# lightson+.sh

# Copyright (c) 2014 devkral at web de
# url: https://github.com/devkral/lightson+

#based on
# Copyright (c) 2011 iye.cba at gmail com
# url: https://github.com/iye/lightsOn
# This script is licensed under GNU GPL version 2.0 or above

# Description: Bash script that prevents the screensaver and display power
# management (DPMS) from being activated while watching fullscreen videos
# on Firefox, Chrome and Chromium. Media players like mplayer, VLC and minitube
# can also be detected.
# One of {x, k, gnome-}screensaver must be installed.

# HOW TO USE: 
# "./lightson+.sh 120 &" will Check every 120 seconds if Mplayer,
# VLC, Firefox or Chromium are fullscreen and delay screensaver and Power Management if so.
# You want the number of seconds to be ~10 seconds less than the time it takes
# your screensaver or Power Management to activate.
# If you don't pass an argument, the checks are done every 50 seconds.


# Select the programs to be checked
mplayer_detection=0
vlc_detection=1
totem_detection=1
firefox_flash_detection=1
chromium_flash_detection=1
chrome_app_detection=0
chrome_app_name="Netflix"
webkit_flash_detection=1 # untested
html5_detection=1 # actually check whether your browser is toggled fullscreen, so simply surfing in fullscreen triggers screensaver inhibition as well (work in progress)
steam_detection=0 # untested
minitube_detection=0  # untested

defaultdelay=50

# realdisp
realdisp=`echo "$DISPLAY" | cut -d. -f1`

inhibitfile="/tmp/lightsoninhibit-$UID-$realdisp"
pidfile="/tmp/lightson-$UID-$realdisp.pid"

# YOU SHOULD NOT NEED TO MODIFY ANYTHING BELOW THIS LINE

# pidlocking
pidcreate() {
    # just one instance can run simultaneously
    if [ ! -e "$pidfile" ]; then
        echo "$$" > "$pidfile"
    else
        if [ -d "/proc/$(cat "$pidfile")" ]; then
            echo "an other instance is running, abort!" >&2
            exit 1
        else
            echo "$$" > "$pidfile"
        fi
    fi
}

pidremove() {
    if [ ! -e "$pidfile" ]; then
        echo "error: missing pidfile" >&2
    elif [ ! -f "$pidfile" ]; then
        echo -e "error: \"$pidfile\" is not a file\n" >&2
    else
        if [ "$(cat "$pidfile")" != "$$" ]; then
            echo "an other instance is running, abort!" >&2
            exit 1
        else
            rm "$pidfile"
        fi
    fi
    exit 0
}

pidcreate
trap "pidremove" EXIT

# enumerate all the attached screens
displays=""
while read id; do
    displays="$displays $id"
done< <(xvinfo | sed -n 's/^screen #\([0-9]\+\)$/\1/p')

# Detect screensaver been used
# pgrep cuts off last character
if [ `pgrep -lc xscreensave` -ge 1 ]; then
    screensaver="xscreensaver"
elif [ `pgrep -lc gnome-screensave` -ge 1 ] || [ `pgrep -lc gnome-shel` -ge 1 ] ;then
    screensaver="gnome-screensaver"
# make sure that the command exists then execute
elif [ `which gnome-screensaver-command` -eq 0 ] && [ `$(which gnome-screensaver-command) -q  | grep -c active` -ge 1 ]; then
    screensaver="gnome-screensaver"
		
elif [ `pgrep -lc kscreensave` -ge 1 ]; then
    screensaver="kscreensaver"
elif [ `pgrep -lc xautoloc` -ge 1 ]; then 
    screensaver="xautolock"
elif [ `pgrep -lc cinnamon-screen` -ge 1 ]; then
    screensaver="cinnamon-screensaver"
else
    screensaver=""
    echo "No screensaver detected"
    exit 1
fi

checkFullscreen() {
    # loop through every display looking for a fullscreen window
    for display in $displays; do
        # get id of active window and clean output
        activ_win_id=`DISPLAY=$realdisp.${display} xprop -root _NET_ACTIVE_WINDOW`
        activ_win_id=${activ_win_id##*# }
        activ_win_id=${activ_win_id:0:9} # eliminate potentially trailing spaces
        
        top_win_id=`DISPLAY=$realdisp.${display} xprop -root _NET_CLIENT_LIST_STACKING`
        top_win_id=${activ_win_id##*, }
        top_win_id=${top_win_id:0:9} # eliminate potentially trailing spaces
        
        # Check if Active Window (the foremost window) is in fullscreen state
        if [ ${#activ_win_id} -eq 9 ]; then
            isActivWinFullscreen=`DISPLAY=$realdisp.${display} xprop -id $activ_win_id | grep _NET_WM_STATE_FULLSCREEN`
        else
            isActiveWinFullscreen=""
        fi
        if [ ${#top_win_id} -eq 9 ]; then
            isTopWinFullscreen=`DISPLAY=$realdisp.${display} xprop -id $top_win_id | grep _NET_WM_STATE_FULLSCREEN`
        else
            isTopWinFullscreen=""
        fi
        
        if [[ "$isActivWinFullscreen" = *NET_WM_STATE_FULLSCREEN* ]] || [[ "$isTopWinFullscreen" = *NET_WM_STATE_FULLSCREEN* ]]; then
            isAppRunning
            var=$?
            if [[ $var -eq 1 ]]; then
                delayScreensaver
            fi
        fi
    done
}

# check if active window is mplayer, vlc or firefox
# TODO only window name in the variable activ_win_id, not whole line. 
# Then change IFs to detect more specifically the apps "<vlc>" and if process name exist

isAppRunning() {
    # Get title of active window
    activ_win_title=`xprop -id $activ_win_id | grep "WM_CLASS(STRING)"` # I used WM_NAME(STRING) before, WM_CLASS is more accurate.
    
    if [ $firefox_flash_detection == 1 ]; then
        if [[ "$activ_win_title" = *unknown* || "$activ_win_title" = *plugin-container* ]]; then
            # Check if plugin-container process is running, pgrep cuts off last character
            [ `pgrep -lc plugin-containe` -ge 1 ] && return 1
        fi
    fi
    
    if [ $chromium_flash_detection == 1 ]; then
        if [ "$activ_win_title" = *chrom* ]; then
            # Check if Chromium Flash process is running
            [ `pgrep -lfc "chromium --type=ppapi"` -ge 1 ] && return 1
        fi
        # Check if Chrome flash is running (by cadejager)
        [ -n `pgrep -lf "chrome --type=ppapi"` ] && return 1
    fi
    
    if [ $webkit_flash_detection == 1 ]; then
        if [ "$activ_win_title" = *WebKitPluginProcess* ]; then
            # Check if WebKit Flash process is running
            [ `pgrep -lfc ".*WebKitPluginProcess.*flashp.*"` -ge 1 ] && (log "isAppRunning(): webkit flash fullscreen detected" && return 1)
        fi
    fi
    
    if [ $html5_detection == 1 ]; then
        if [ "$activ_win_title" = *Chrome* || "$activ_win_title" = *hromium-browser* || "$activ_win_title" = *Firefox* || "$activ_win_title" = *epiphany* || "$activ_win_title" = *opera* ]; then
            # check if firefox or chromium is running.
            [ `pgrep -lc chrome` -ge 1 || `pgrep -lc firefox` -ge 1 || `pgrep -lc chromium-browser` -ge 1  || `pgrep -lc opera` -ge 1 || `pgrep -lc epiphany` -ge 1 ] && return 1
                fi
        fi
        
        if [ $chrome_app_detection == 1 ]; then
            if [ ! -z $chrome_app_name && "$activ_win_title" = *$chrome_app_name* ]; then
                # check if google chrome is runnig in app mode
                [ `pgrep -lfc "chrome --app"` -ge 1 ] && return 1
            fi
        fi
        
        if [ $mplayer_detection == 1 ]; then
            if [ "$activ_win_title" = *mplayer* || "$activ_win_title" = *MPlayer* ]; then
                # check if mplayer is running.
                [ `prep -lc mplayer` -ge 1 ] && return 1
            fi
        fi
        
        if [ $vlc_detection == 1 ]; then
            if [ "$activ_win_title" = *vlc* ]; then
                # check if vlc is running.
                [ `pgrep -lc vlc` -ge 1 ] && return 1
            fi
        fi
        
        if [ $totem_detection == 1 ]; then
            if [ "$activ_win_title" = *totem* ]; then
                # check if totem is running.
                [ `pgrep -lc totem` -ge 1 ] && return 1
            fi
        fi
        
        if [ $steam_detection == 1 ]; then
            if [ "$activ_win_title" = *steam* ]; then
                # check if steam is running.
                [ `pgrep -lc steam` -ge 1 ] && return 1
            fi
        fi
        
        if [ $minitube_detection == 1 ]; then
            if [ "$activ_win_title" = *minitube* ]; then
                # check if minitube is running.
                [ `pgrep -lc minitube` -ge 1 ] && (log "isAppRunning(): minitube fullscreen detected" && return 1)
            fi
        fi
        
        return 0
}

delayScreensaver() {
    # reset inactivity time counter so screensaver is not started
    case $screensaver in
        "xscreensaver" )
            # This tells xscreensaver to pretend that there has just been user activity.
            # This means that if the screensaver is active
            # (the screen is blanked), then this command will cause the screen
            # to un-blank as if there had been keyboard or mouse activity.
            # If the screen is locked, then the password dialog will pop up first,
            # as usual. If the screen is not blanked, then this simulated user
            # activity will re-start the countdown (so, issuing the -deactivate
            # command periodically is one way to prevent the screen from blanking.)

            xscreensaver-command -deactivate > /dev/null;;
    "gnome-screensaver" )
            # new way, first try
            dbus-send --session --dest=org.freedesktop.ScreenSaver --reply-timeout=2000 --type=method_call /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity > /dev/null
            # old way second try
            dbus-send --session --type=method_call --dest=org.gnome.ScreenSaver --reply-timeout=20000 /org/gnome/ScreenSaver org.gnome.ScreenSaver.SimulateUserActivity > /dev/null;;
    "kscreensaver" )
        qdbus org.freedesktop.ScreenSaver /ScreenSaver SimulateUserActivity > /dev/null;;
    "cinnamon-screensaver" )
        # use standard inhibit message, maybe merge with gnome-screensaver
        dbus-send --session --dest=org.freedesktop.ScreenSaver --reply-timeout=2000 --type=method_call /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity > /dev/null;;
    "xautolock" )
        xautolock -disable
        xautolock -enable;;
    esac
    
    # Check if DPMS is on. If it is, deactivate and reactivate again. If it is not, do nothing.
    dpmsStatus=`xset -q | grep -ce 'DPMS is Enabled'`
    [ $dpmsStatus == 1 ] && (xset -dpms && xset dpms)
}

# check if argument is valid, default to 50s interval if none is given
case $1 in
    "" )
        delay=$defaultdelay;;
    *[^0-9]* )
        echo "The Argument \"$1\" is not valid, not an integer"
        echo "Please use the time in seconds you want the checks to repeat."
        echo "You want it to be ~10 seconds less than the time it takes your screensaver or DPMS to activate"
        exit 1;;
    * )
        delay=$1;;
esac

echo "start lightsOn mainloop"
while true; do
    [ -f "$inhibitfile" ] && dealyScreensaver || checkFullscreen
    sleep $delay
done

exit 0
