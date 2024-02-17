if [ ! -d "neovim" ]; then
    git clone https://github.com/neovim/neovim.git
    cd neovim || exit
    make CMAKE_BUILD_TYPE=RelWithDebInfo
    sudo make install
    cd .. || exit
    # Optionally remove the neovim directory after installation
    # rm -rf neovim
else
    echo "Neovim directory already exists. Skipping clone and compile."
fi
