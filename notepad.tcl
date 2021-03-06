#!/usr/bin/env wish
#
# Copyright (c) 2012-2014 Pat Thoyts <patthoyts@users.sourceforge.net>
#
# A Tk based clone of notepad with Unix or Windows line ending detection and
# byte-order-mark (BOM) handling.
#

package require Tk 8.5
variable UID
if {![info exists UID]} { set UID 0 }

# Open a file, selecting utf-8, unicode or system encoding according
# to any BOM.
proc open_bom {filename {mode "r"}} {
    set f [open $filename $mode]
    fconfigure $f -encoding binary -translation binary
    binary scan [read $f 3] H* bom
    switch -glob -- $bom {
        "efbbbf" {
            fconfigure $f -encoding utf-8
        }
        "fffe*"  {
            seek $f 2
            fconfigure $f -encoding unicode
        }
        default {
            seek $f 0
            fconfigure $f -encoding [encoding system]
        }
    }
    return $f
}

proc New {app} {
    upvar #0 $app state
    $app.f.txt delete 1.0 end
    $app.f.txt edit reset
    unset -nocomplain state
    set state(filename) ""
    set state(encoding) "utf-8"
    set state(translation) auto
    set state(bom) 0
    wm title $app "Unnamed - Notepad"
    UpdateStatusPos $app insert
}

proc Open {app} {
    set path [tk_getOpenFile]
    if {$path ne ""} {
        OpenFile $app $path
    }
}

# Load a file into the text widget accounting for any BOM and detect the
# line ending format in use.
proc OpenFile {app path} {
    upvar #0 $app state
    if {![file exists $path]} {
        New $app
        set state(filename) $path
    } else {
        set f [open_bom $path r]
        set state(filename) $path
        set state(encoding) [fconfigure $f -encoding]
        set state(start) [tell $f]
        set state(bom) [expr {$state(start) != 0}]
        gets $f line
        set state(translation) [expr {([string index $line end] == "\r") ? "crlf" : "lf"}]
        seek $f $state(start)
        fconfigure $f -translation $state(translation)
        set data [read $f]
        close $f
        if {$state(showwhitespace)} {
            set data [ConvertWhitespace $data true]
        }
        $app.f.txt delete 1.0 end
        $app.f.txt insert end $data
        $app.f.txt edit modified 0
        $app.f.txt edit reset
        $app.f.txt see 1.0
    }
    wm title $app [format {%s - Notepad} [file tail $path]]
    UpdateStatusPos $app insert
}

proc Save {app} {
    upvar #0 $app state
    if {$state(filename) eq ""} {
        SaveAs $app
    } else {
        SaveFile $app $state(filename)
    }
}

proc SaveAs {app} {
    upvar #0 $app state
    set path [tk_getSaveFile -confirmoverwrite true]
    if {$path ne ""} {
        SaveFile $app $path
        set state(filename) $path
    }
}

# Save the text widget contents using the recorded encoding, line-ending format and
# BOM marker if required.
proc SaveFile {app path} {
    upvar #0 $app state
    set f [open $path w]
    fconfigure $f -encoding $state(encoding) -translation $state(translation)
    if {$state(bom)} { puts -nonewline $f "\ufeff" }
    set data [$app.f.txt get 1.0 "end - 1 char"]
    if {$state(showwhitespace)} {
        set data [ConvertWhitespace $data false]
    }
    puts -nonewline $f $data
    close $f
    $app.f.txt edit modified 0
}

# Exit function checks for unsaved changes.
proc Exit {app} {
    upvar #0 $app state
    if {[$app.f.txt edit modified]} {
        set choice [tk_messageBox -icon question -type okcancel \
                       -message "Unsaved changes remain. Select Cancel to abort exit."]
        if {$choice eq "cancel"} {
            return
        }
    }
    unset state
    destroy $app
}
proc OnWrap {app} {
    upvar #0 $app state
    $app.f.txt configure -wrap $state(wrap)
}

proc OnFont {app} {
    tk fontchooser configure -parent $app -command [list OnFontSelected $app]
    tk fontchooser show
}

proc OnFontSelected {app font} {
    if {$font ne ""} {
        $app.f.txt configure -font [font actual $font]
    }
}

proc OnPostEdit {app} {
    if {[$app.f.txt edit modified]} {set state normal} else {set state disabled}
    $app.menu.edit entryconfigure 0 -state $state
}

# Toggle the visibility of the status bar
proc OnStatusbar {app} {
    upvar #0 $app state
    if {[winfo ismapped $app.status]} {
        grid forget $app.status
    } else {
        grid $app.status -sticky ew
    }
    set state(statusbar) [winfo ismapped $app.status]
}

proc CreateStatusbar {app w} {
    set st [ttk::frame $w]
    ttk::label $st.pane0 -anchor w -textvariable [namespace which -variable $app](pane0)
    ttk::separator $st.sep0 -orient vertical
    ttk::label $st.pane1 -anchor w -textvariable [namespace which -variable $app](pos)
    ttk::separator $st.sep1 -orient vertical
    ttk::label $st.pane2 -anchor w -textvariable [namespace which -variable $app](encoding)
    ttk::separator $st.sep2 -orient vertical
    ttk::label $st.pane3 -anchor w -textvariable [namespace which -variable $app](translation)
    ttk::sizegrip $st.sg
    grid $st.pane0 $st.sep0 $st.pane1 $st.sep1 $st.pane2 $st.sep2 $st.pane3 $st.sg -sticky news
    grid columnconfigure $st 0 -weight 1
    return $st
}

proc UpdateStatusPos {app pos} {
    upvar #0 $app state
    if {$pos ne ""} {
        set pos [$app.f.txt index $pos]
        set state(pos) [format {Ln %s, Col %s} {*}[split $pos .]]
    } else {
        set state(pos) ""
    }
}

proc About {app} {
    tk_messageBox -icon info -type ok \
        -message "Simple Notepad v1.0" \
        -detail "Copyright (c) 2014 Pat Thoyts <patthoyts@users.sourceforge.net>"
}

proc OnMotion {app w x y} {
    if {[catch {
        if {"$w" eq "$app.f.txt"} {
            $app.f state hover
        } else {
            $app.f state !hover
        }
    } err]} { puts stderr $err }
}

proc OnTextWidgetConfigure {app x y w h} {
    upvar #0 $app state
    if {$state(showcolumnlimit)} {
        set pos [font measure [$app.f.txt cget -font] [string repeat "0" 76]]
        $app.f.bar configure -height $h
        place $app.f.bar -x [expr {$x + $pos}] -y $y
    }
}

proc OnShowColumnLimit {app} {
    upvar #0 $app state
    if {$state(showcolumnlimit)} {
        set w $app.f.txt
        OnTextWidgetConfigure $app \
            [winfo x $w] [winfo y $w] [winfo width $w] [winfo height $w]
    } else {
        place forget $app.f.bar
    }
}

proc ConvertWhitespace {data showwhitespace} {
    if {$showwhitespace} {
        set data [string map {\u0020 \u00b7 \t \u00bb\t} $data]
    } else {
        set data [string map {\u00b7 \u0020 \u00bb\t \t} $data]
    }
    return $data
}

proc OnKeyWhitespace {w char} {
    upvar #0 [winfo toplevel $w] state
    if {$state(showwhitespace)} {
        switch -exact -- $char {
            \u0020 {set char \u00b7}
            \u0009 {set char \u00bb\t}
        }
    }
    tk::TextInsert $w $char
    UpdateStatusPos [winfo toplevel $w] insert
}

proc OnShowWhitespace {app} {
    upvar #0 $app state
    set data [$app.f.txt get 1.0 "end - 1c"]
    $app.f.txt replace 1.0 end [ConvertWhitespace $data $state(showwhitespace)]
}

proc Pop {varname {nth 0}} {
    upvar $varname args
    set r [lindex $args $nth]
    set args [lreplace $args $nth $nth]
    return $r
}

proc ProcessArguments {app arglist} {
    upvar #0 $app state
    while {[string match -* [set option [lindex $arglist 0]]]} {
        switch -exact -- $option {
            -whitespace { set state(showwhitespace) [expr {!![Pop arglist 1]}] }
            -columnmark { set state(showcolumnlimit) [expr {!![Pop arglist 1]}] }
            --          { Pop arglist; break }
            default { break }
        }
        Pop arglist
    }
    if {[llength $arglist] > 1} {
        return -code error "usage: notepad ?-whitespace 0|1? ?-columnmark 0|1? filename {$arglist}"
    }
    return [lindex $arglist 0]
}

proc main {args} {
    variable UID
    option add *Menu.tearOff 0 widgetDefault

    set app [toplevel .ed[incr UID] -class Notepad]
    upvar #0 $app state
    array set state {statusbar 1 showwhitespace 0 showcolumnlimit 0}
    wm withdraw $app
    wm title $app "Notepad"

    set filename [ProcessArguments $app $args]

    $app configure -menu [set menu [menu $app.menu]]
    $menu add cascade -label File -menu [menu $menu.file]
    $menu.file add command -label "New" -command [list New $app]
    $menu.file add command -label "Open..." -command [list Open $app]
    $menu.file add command -label "Save" -command [list Save $app]
    $menu.file add command -label "Save As..." -command [list SaveAs $app]
    $menu.file add separator
    $menu.file add command -label "Exit" -command [list Exit $app]
    $menu add cascade -label Edit -menu [menu $menu.edit -postcommand [list OnPostEdit $app]]
    $menu.edit add command -label "Undo" -command [list event generate $app.f.txt <<Undo>>]
    $menu.edit add separator
    $menu.edit add command -label "Cut" -command [list event generate $app.f.txt <<Cut>>]
    $menu.edit add command -label "Copy" -command [list event generate $app.f.txt <<Copy>>]
    $menu.edit add command -label "Paste" -command [list event generate $app.f.txt <<Paste>>]
    $menu.edit add command -label "Delete" -command [list event generate $app.f.txt <<Clear>>]
    $menu add cascade -label Format -menu [menu $menu.format]
    $menu.format add checkbutton -label "Word Wrap" -onvalue word -offvalue char \
        -variable [namespace which -variable $app](wrap) \
        -command [list OnWrap $app]
    $menu.format add command -label "Font..." -command [list OnFont $app] \
        -state [expr {[package vcompare [package provide Tk] 8.6] > 0 ? "normal" : "disabled"}]
    $menu.format add separator
    $menu.format add checkbutton -label "Write Unicode BOM" -onvalue 1 -offvalue 0 \
        -variable [namespace which -variable $app](bom)
    $menu.format add cascade -label "Line Ending" -menu [menu $menu.format.line]
    $menu.format.line add radiobutton -label "Unix (LF)" -value lf \
        -variable [namespace which -variable $app](translation)
    $menu.format.line add radiobutton -label "Windows (CRLF)" -value crlf \
        -variable [namespace which -variable $app](translation)
    $menu add cascade -label "View" -menu [menu $menu.view]
    $menu.view add checkbutton -label "Status Bar" -onvalue 1 -offvalue 0 \
        -variable [namespace which -variable $app](statusbar) -command [list OnStatusbar $app]
    $menu.view add checkbutton -label "Show whitespace" -onvalue 1 -offvalue 0 \
        -variable [namespace which -variable $app](showwhitespace) -command [list OnShowWhitespace $app]
    $menu.view add checkbutton -label "Show column limit" -onvalue 1 -offvalue 0 \
        -variable [namespace which -variable $app](showcolumnlimit) -command [list OnShowColumnLimit $app]
    $menu add cascade -label "Help" -menu [menu $menu.help]
    $menu.help add command -label "View Help" -command {tk_messageBox -message "no help"}
    $menu.help add separator
    $menu.help add command -label "About Help" -command [list About $app]

    # Match the Vista/Windows 7 theme element around the edit area.
    # Default to something sensible on X11.
    ttk::style theme settings default {
        ttk::style layout TextFrame {
            TextFrame.field -sticky news -border 0 -children {
                TextFrame.fill -sticky news -children {
                    TextFrame.padding -sticky news
                }
            }
        }
        ttk::style configure TextFrame -padding 1 -relief sunken
        ttk::style map TextFrame -background {}
    }
    catch {
        ttk::style theme settings vista {
            ttk::style configure TextFrame -padding 2
            ttk::style element create TextFrame.field vsapi \
                EDIT 6 {disabled 4 focus 3 active 2 {} 1} -padding 2
        }
    }
    bind TextFrame <Enter> {%W instate !disabled {%W state active}}
    bind TextFrame <Leave> {%W state !active}

    set f [ttk::frame $app.f -style TextFrame -class TextFrame -padding 1]
    set txt [text $f.txt -undo true -borderwidth 0 -relief flat]
    set vs [ttk::scrollbar $f.vs -command [list $txt yview]]
    $txt configure -yscrollcommand [list $vs set]

    set bar [frame $f.bar -borderwidth 0 -background grey60 \
                 -width 1 -height 10 -cursor [$txt cget -cursor]]

    grid $txt $vs -sticky news
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 0 -weight 1

    set status [CreateStatusbar $app $app.status]
    set state(statusbar) 1

    grid $f -sticky news
    grid $status -sticky ew
    grid columnconfigure $app 0 -weight 1
    grid rowconfigure $app 0 -weight 1

    bind $app.f.txt <Configure> [list +OnTextWidgetConfigure $app %x %y %w %h]
    bind $app.f.txt <ButtonRelease-1> {+UpdateStatusPos [winfo toplevel %W] insert}
    bind $app.f.txt <ButtonPress-1> {+UpdateStatusPos [winfo toplevel %W] [%W index @%x,%y]}
    bind $app.f.txt <Key-space> {OnKeyWhitespace %W %A; break}
    bind $app.f.txt <Key-Tab> {OnKeyWhitespace %W %A; break}
    bind $app <Key> {+UpdateStatusPos [winfo toplevel %W] insert}

    if {[tk windowingsystem] eq "win32"} {bind $app <Control-F2> {console show}}
    bind $app <Control-o> [list Open $app]
    bind $app <Control-s> [list Save $app]
    bind $app <Control-S> [list SaveAs $app]
    wm protocol $app DELETE [list Exit $app]
    if {$filename ne ""} {
        after idle [list OpenFile $app $filename]
    }
    focus -force $app.f.txt
    wm deiconify $app
    if {[tk windowingsystem] eq "aqua"} {
        exec /usr/bin/osascript -e {
            tell app "Finder"
                set frontmost of process "Wish" to true
            end tell
        }
    }
    tkwait window $app
}

if {!$tcl_interactive} {
    if {![info exists initialized]} {
        set initialized 1
        wm withdraw .
        set r [catch [linsert $argv 0 main] err]
        if {$r} {
            tk_messageBox -icon error -message $err -detail $::errorInfo
        }
        exit $r
    }
}
