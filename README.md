                   
                                                      db                               
                                                                                       
                                   ,p6"bo   ,6"Yb.  `7MM  `7MMpMMMb.                   
                                  6M'  OO  8)   MM    MM    MM    MM                   
                                  8M        ,pm9MM    MM    MM    MM                   
                                  YM.    , 8M   MM    MM    MM    MM                   
                                   YMbmd'  `Moo9^Yo..JMML..JMML  JMML.                 
                                                                                       
                        This Program Was Made January 2025 By Rhett Applestone         
                                                                                       
                                               MIT License                             
                                   Copyright (c) 2025 Rhett Applestone                 

### This program will switch your dotfiles and configs for mine

### What is cain and what does it do?

Think of cain like a little robot that helps you keep track of dotfiles, keybindings, and desktop enviornemnt settings and install them easily on a new computer

I made cain because I was having a hard time keeping track of individual repositories of all my configs and because it was annoying to do

cain stands for Collect And INstall and it does those two things

The install script will download all required programs, and put all of your configuration files in their respective places

The install script also gives you a command called "cain" that will grab the most reecent version of those files, commit them to git in the cain directory, and push them.



### How do I use cain (linux mint)


Change to your home directory and clone the cain repo
```
cd 
git clone https://github.com/v3ai/cain
```

Go inside the cain directory and run the install script
```
cd cain
./install
```

Go about your life normally, and if you update a keybinding run cain in the terminal so you can download all your bindings later
```
cain
```
