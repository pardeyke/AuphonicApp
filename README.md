# Configure (one-time)
cmake -B build

# Build
./Packaging/build.sh

# Distribute
./Packaging/build.sh && ./Packaging/distribute.sh
