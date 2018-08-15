#! /bin/sh
# \
exec tclsh "$0" ${1+"$@"}

package require tdom
package require vfs
package require vfs::zip
package require fileutil


set bookDir [file join $env(HOME) Books]

proc lfilter {list script} {
    set res [list]
    foreach e $list {
        if {[uplevel 1 $script [list $e]]} {
            lappend res $e
        }
    }
    return $res
}

proc notEmpty {v} {
    return [expr {$v ne ""}]
}

proc getFb2Info {filename} {
    set xml [fileutil::cat $filename]
    set doc [dom parse $xml]
    set root [$doc documentElement root]
    set namespace [$root getAttribute xmlns]
    set titleInfo [$root selectNodes -namespace [list l $namespace] //l:description/l:title-info]
    switch -- [llength $titleInfo] {
        0 {
            return [dict create code error data "<description> not found"]
        }

        1 {
            set genres [lmap g [$titleInfo selectNodes -namespace [list l $namespace] //l:genre] {
                $g text
            }]
            set authors [lmap author [$titleInfo selectNodes -namespace [list l $namespace] l:author] {
                join [lmap name {last-name first-name middle-name} {
                    join [lmap v [$author selectNodes -namespace [list l $namespace] l:$name] {
                        $v asText
                    }] " "
                }] " "
            }]
            set title [[lindex [$titleInfo selectNodes -namespace [list l $namespace] //l:book-title] 0] asText]

            return [dict create code ok data [dict create authors $authors genres $genres title $title]]
        }

        default {
            return [dict create code error data "More than 1 <description> tag found"]
        }
    }
}

if {$argc == 1} {
    set src [lindex $argv 0]
    set filename [file tail $src]
    vfs::zip::Mount $src [file join / $filename]
    set files [glob -nocomplain -dir [file join / $filename] *.fb2]
    switch -- [llength $files] {
        0 {
            puts stderr "Empty zip file"
            exit 1
        }

        1 {
            set fb2 [getFb2Info [lindex $files 0]]
            puts "Parse FB2 info: [dict get $fb2 code]"
            puts "Book title: [dict get $fb2 data title]"
            if {[dict get $fb2 code] eq "ok"} {
                set authors [lmap a [dict get $fb2 data authors] {
                    string map {" " _} [lfilter $a notEmpty]
                }]
                foreach author $authors {
                    set dir [file join $::bookDir $author]
                    puts "Create directory: $dir"
                    file mkdir $dir
                }
                set otherAuthors [lassign $authors firstAuthor]
                set newBookname "[dict get $fb2 data title].fb2.zip"
                if {![catch {file rename $filename [file join $::bookDir $firstAuthor $newBookname]}]} {
                    if {[llength $otherAuthors] > 0} {
                        set bookFilename [file tail $filename]
                        foreach author $otherAuthors {
                            file link [file join $bookDir $author $newBookname] [file join $bookDir $firstAuthor $newBookname]
                        }
                    }
                } else {
                    puts stderr "Error: file \"[file join $::bookDir $firstAuthor [file tail $newBookname]]\" already exists."
                }
            } else {
                puts stderr "Error parsing $filename: [dict get $fb2 data]"
                exit 1
            }
        }

        default {
            puts stderr "Too many files in zip archive: $files"
            exit 1
        }
    }
} else {
    puts stderr "Usage: $::argv0 book.fb2.zip"
    exit 1
}
