#!/usr/bin/env bash

# Define the directory to store fonts
fonts_dir="${HOME}/.local/share/fonts"
# Create the directory if it does not exist
if [ ! -d "${fonts_dir}" ]; then
    echo "mkdir -p $fonts_dir"
    mkdir -p "${fonts_dir}"
else
    echo "Found fonts dir $fonts_dir"
fi

# Version is now tied to the nerd-fonts release version
version=3.2.0
# Adjust the filename to match the expected zip file from nerd-fonts
zip=FiraMono.zip
# Update the URL to point to the new source
curl --fail --location --show-error https://github.com/ryanoasis/nerd-fonts/releases/download/v${version}/${zip} --output ${zip}
# Unzip the font files into the designated directory
unzip -o -q -d ${fonts_dir} ${zip}
# Clean up by removing the zip file
rm ${zip}

# Update the font cache
echo "fc-cache -f"
fc-cache -f

