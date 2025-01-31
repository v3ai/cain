                   
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

Think of cain like a little robot that helps you keep track of dotfiles, keybindings, and desktop enviornemnt settings and easily install them on a new computer

I made cain because I was having a hard time keeping track and updating individual repositories for configs

Cain makes it easy to make your computer exactly like you like it on a fresh install

cain stands for Collect And INstall and it does those two things

First, the install script will download all required programs and put all of your configuration files in their respective places

then it gives you a command called "cain" that will grab the most reecent version of those files, commit them to git in the cain directory, and (optionally) push them.


## NOTE: This program will switch your dotfiles and configs to mine

### How do I use cain (linux mint)

(One line install), paste into terminal
```
cd && sudo apt install git -y && git clone https://github.com/v3ai/cain && cd cain && ./install
```


Go about your life normally, and if you update a keybinding, run cain in the terminal so you can have all your configs in one place for an easy install
```
cain
```

### Don't move the cain directory from your home directory or it will break.
Ascii art made with figlet -f Georgia11.flf cain (you may have to download that .flf file)

my configs change pretty frequently, but the majority of them are at https://rhettapplestone.com/keys.html




