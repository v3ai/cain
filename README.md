                   
                                                      db                               
                                                                                       
                                   ,p6"bo   ,6"Yb.  `7MM  `7MMpMMMb.                   
                                  6M'  OO  8)   MM    MM    MM    MM                   
                                  8M        ,pm9MM    MM    MM    MM                   
                                  YM.    , 8M   MM    MM    MM    MM                   
                                   YMbmd'  `Moo9^Yo..JMML..JMML  JMML.                 
                                                                                       
                        This Program Was Made January 2025 By Rhett Applestone         
                                                                                       
                                               MIT License                             
                                   Copyright (c) 2025 Rhett Applestone                 


### What is cain and what does it do?

cain stands for Collect And INstall

Think of cain like a little robot that helps you keep track of dotfiles, keybindings, and desktop environment settings and easily install them on a new computer

I made cain because I was having a hard time keeping track and updating individual repositories for configs

Cain makes it easy to make your computer exactly like you like it on a fresh install and it does those two things

First, the install script will download all required programs and put all of your configuration files in their respective places

then it gives you a command called "cain" and (optionally) sets up a crontab that will grab the most recent version of those files automatically, and commit them to git in the cain directory.


## NOTE: This program will switch your dotfiles and configs to mine

### How do I use cain (linux mint)

(One line install), paste into terminal
```
cd && sudo apt install git -y && git clone https://github.com/v3ai/cain && cd cain && ./install
```
if you want to make cain push to github whenever you change a file, edit /usr/local/bin/cain
and remove the remove the pound sign before the line "git push"

Go about your life normally, and if you update a keybinding, run (or it will do it automatically if you use the crontab)

```
cain
```

### Don't move the cain directory from your home directory or it will break.
Ascii art made with figlet -f Georgia11.flf cain (you may have to download that .flf file)



