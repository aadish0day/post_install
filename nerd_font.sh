#!/usr/bin/env bash

# Define the directory to store fonts
fonts_dir="${HOME}/.local/share/fonts"

# Create the directory if it does not exist
if [ ! -d "${fonts_dir}" ]; then
    echo "Creating directory: $fonts_dir"
    mkdir -p "${fonts_dir}"
else
    echo "Found existing fonts directory: $fonts_dir"
fi

# GitHub repository from which to fetch the latest release
repo="ryanoasis/nerd-fonts"

# Fetch the latest release tag from GitHub API
echo "Fetching the latest release information..."
latest_release_json=$(curl -s "https://api.github.com/repos/$repo/releases/latest")

# Extract the tag name (version) from the JSON response
latest_version=$(echo "$latest_release_json" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

# Check if we got a version number
if [[ -z "$latest_version" ]]; then
    echo "Failed to fetch the latest version number." >&2
    exit 1
fi

echo "Latest version is $latest_version"

# Define the filename based on expected zip file format
zip="FiraMono.zip"

# Download the zip file using the latest version number
echo "Downloading Fira Mono Nerd Font version $latest_version..."
if curl --fail --location --show-error -o "${zip}" "https://github.com/$repo/releases/download/$latest_version/$zip"; then
    echo "Download successful."
else
    echo "Failed to download the font zip file." >&2
    exit 1
fi

# Unzip the font files into the designated directory
echo "Unzipping the font files..."
unzip -o -q -d "${fonts_dir}" "${zip}"

# Clean up by removing the zip file after extraction
echo "Removing zip file..."
rm "${zip}"

# Update the font cache
echo "Updating font cache..."
fc-cache -f

echo "Font installation completed."

