# Render: vhs demo/demo.tape   (from the repo root; needs vhs + ttyd). Sample data only, see demo/env.zsh.
Output demo/demo.gif
Set Shell zsh
Set FontSize 17
Set Width 1180
Set Height 470
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "setopt interactivecomments; export PS1='%F{cyan}❯%f '; source demo/env.zsh; clear" Enter
Sleep 2s
Show

Type "# four Claude logins on one machine" Sleep 600ms Enter
Type "cca" Sleep 400ms Enter Sleep 1.8s
Type "cca work        # this terminal runs Claude Code as 'work'" Sleep 400ms Enter Sleep 1.5s
Type "ccm             # claude-mem bills 'work'... which is at 96%" Sleep 400ms Enter Sleep 4.5s
Type "clear" Enter
Type "ccm personal    # move ONLY the memory observer" Sleep 400ms Enter Sleep 2.5s
Type "ccm             # pause gone, queue draining, nothing lost" Sleep 400ms Enter Sleep 5s
Hide
Type "kill $DEMO_SERVER" Enter
