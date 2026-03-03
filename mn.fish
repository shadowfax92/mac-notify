function mn
    if test (count $argv) -eq 0
        mac-notify --help
        return
    end

    set -l subcmd $argv[1]
    set -l rest $argv[2..]

    switch $subcmd
        case s send
            mac-notify send $rest
        case ls l list
            mac-notify list $rest
        case c clear
            mac-notify clear $rest
        case st status
            mac-notify status $rest
        case cfg config
            mac-notify config $rest
        case '*'
            mac-notify $argv
    end
end
