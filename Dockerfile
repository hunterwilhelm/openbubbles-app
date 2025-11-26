# Use explicit platform for Apple Silicon Macs
FROM --platform=linux/amd64 ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install basic dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    wget \
    sudo \
    build-essential \
    pkg-config \
    libssl-dev \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Set up Rust (stable toolchain)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# Set up Flutter 3.24.0
ENV FLUTTER_VERSION=3.24.4
ENV FLUTTER_HOME=/opt/flutter
RUN mkdir -p ${FLUTTER_HOME} && \
    cd /opt && \
    curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz | tar -xJ && \
    chmod -R 755 ${FLUTTER_HOME} && \
    git config --global --add safe.directory ${FLUTTER_HOME}
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"

# Set up Java 21 (Temurin)
ENV JAVA_VERSION=21
ENV JAVA_HOME=/opt/java
RUN mkdir -p ${JAVA_HOME} && \
    curl -L "https://api.adoptium.net/v3/binary/latest/${JAVA_VERSION}/ga/linux/x64/jdk/hotspot/normal/eclipse" | tar -xz -C ${JAVA_HOME} --strip-components=1
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Set up Android SDK
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

# Install Android SDK command-line tools
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    cd ${ANDROID_HOME}/cmdline-tools && \
    curl -L https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip -o cmdline-tools.zip && \
    unzip -q cmdline-tools.zip && \
    mv cmdline-tools latest && \
    rm cmdline-tools.zip

# Accept Android licenses and install required SDK components
# Split into separate RUN commands to avoid issues with pipe and error handling
RUN mkdir -p ${ANDROID_HOME}/licenses && \
    echo "24333f8a63b6825ea9c5514f83c2829b004d1fee" > ${ANDROID_HOME}/licenses/android-sdk-license && \
    echo "84831b9409646a918e30573bab4c9c91346d8abd" > ${ANDROID_HOME}/licenses/android-sdk-preview-license && \
    echo "d975f751698a77b662f1254ddbeed3901e976f5a" > ${ANDROID_HOME}/licenses/android-googletv-license && \
    echo "601085b94cd77f0b54ff86406957099ebe79c4d6" > ${ANDROID_HOME}/licenses/android-sdk-arm-dbt-license

RUN ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_HOME} "platform-tools" "platforms;android-36" "build-tools;34.0.0"

# Configure git for the build process
RUN git config --global --add safe.directory '*' && \
    git config --global user.email "build@docker.local" && \
    git config --global user.name "Docker Build"

# Configure Gradle to avoid file watching issues in Docker
RUN mkdir -p /root/.gradle && \
    echo "org.gradle.vfs.watch=false" > /root/.gradle/gradle.properties && \
    echo "org.gradle.daemon=true" >> /root/.gradle/gradle.properties && \
    echo "org.gradle.parallel=true" >> /root/.gradle/gradle.properties && \
    echo "org.gradle.configureondemand=true" >> /root/.gradle/gradle.properties

# Set working directory
WORKDIR /app

# Copy the project files
COPY . .

# Make build.sh executable
RUN chmod +x build.sh

# Run Flutter doctor to verify setup (optional, for debugging)
RUN flutter doctor

# Create a wrapper script that handles submodule updates with local changes
RUN echo '#!/bin/bash\n\
set -e\n\
# Handle submodules with local changes by deinitializing and cleaning them\n\
if [ -d "rustpush" ]; then\n\
  # Remove the submodule directory completely to start fresh\n\
  rm -rf rustpush\n\
fi\n\
# Now run the actual build script which will initialize and update submodules\n\
./build.sh' > /app/docker-build.sh && chmod +x /app/docker-build.sh

# Run the build script
CMD ["/app/docker-build.sh"]

