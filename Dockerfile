FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install basic dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    zsh \
    wget \
    vim \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for Claude Code (cannot run as root with --dangerously-skip-permissions)
RUN useradd -m -s /bin/zsh ralph && \
    usermod -aG sudo ralph

# Set zsh as default shell for ralph user
RUN usermod -s /bin/zsh ralph

# Install Node.js (required for amp tool)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Install Go
RUN curl -fsSL https://go.dev/dl/go1.23.6.linux-amd64.tar.gz -o /tmp/go.tar.gz && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz

# Add Go to PATH
ENV PATH="/usr/local/go/bin:${PATH}"

# Create workspace directory and copy all files there
WORKDIR /workspace
COPY . /workspace/

# Make the script executable
RUN chmod +x /workspace/ralph.sh

# Give ownership of workspace to ralph user and make it world-writable
RUN chown -R ralph:ralph /workspace && \
    chmod -R 777 /workspace

# Create /application directory with write permissions for volume mounts
RUN mkdir -p /application && \
    chown ralph:ralph /application && \
    chmod 777 /application

# Set up PATH to include workspace scripts and npm global binaries
ENV PATH="/workspace:/usr/local/bin:/usr/local/go/bin:${PATH}"

# Create global zshrc to prevent newuser-install prompt for any user
RUN mkdir -p /etc/zsh && \
    echo 'export PATH=$PATH:/workspace:/usr/local/bin:$HOME/.local/bin:/usr/local/go/bin' > /etc/zsh/zshrc && \
    echo 'export HOME=${HOME:-/tmp}' >> /etc/zsh/zshrc && \
    echo 'alias ll="ls -la"' >> /etc/zsh/zshrc && \
    echo '# Source oh-my-zsh if installed for this user' >> /etc/zsh/zshrc && \
    echo 'if [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then' >> /etc/zsh/zshrc && \
    echo '  source "$HOME/.oh-my-zsh/oh-my-zsh.sh"' >> /etc/zsh/zshrc && \
    echo 'fi' >> /etc/zsh/zshrc

# Install Oh My Zsh for root
RUN sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" "" --unattended

# Install Claude Code and Oh My Zsh for ralph user

USER ralph
RUN curl -fsSL https://claude.ai/install.sh | bash
RUN sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" "" --unattended

# Set up .zshenv - always sourced, unsets RALPH_GIT_ALLOWED immediately
RUN echo 'unset RALPH_GIT_ALLOWED  # Disable git after initial shell setup' > /home/ralph/.zshenv && \
    chown ralph:ralph /home/ralph/.zshenv

# Set up .zshrc for ralph user
RUN echo 'export PATH=$PATH:/workspace:/usr/local/bin:$HOME/.local/bin:/usr/local/go/bin' > /home/ralph/.zshrc && \
echo 'export ZSH_DISABLE_COMPFIX=true' >> /home/ralph/.zshrc && \
echo 'source ~/.oh-my-zsh/oh-my-zsh.sh' >> /home/ralph/.zshrc && \
chown ralph:ralph /home/ralph/.zshrc

# Replace git with a wrapper script that checks for RALPH_GIT_ALLOWED env var
USER root
RUN mv /usr/bin/git /usr/local/bin/.git.bin && \
    printf '#!/bin/sh\n' > /usr/bin/git && \
    printf '# Git wrapper - only works when RALPH_GIT_ALLOWED is set\n' >> /usr/bin/git && \
    printf 'if [ -n "$RALPH_GIT_ALLOWED" ]; then\n' >> /usr/bin/git && \
    printf '    exec /usr/local/bin/.git.bin "$@"\n' >> /usr/bin/git && \
    printf 'else\n' >> /usr/bin/git && \
    printf '    echo "ERROR: git is not accessible - this is a security feature! Do NOT use git directly; Do NOT attempt to bypass this restriction." >&2\n' >> /usr/bin/git && \
    printf '    exit 1\n' >> /usr/bin/git && \
    printf 'fi\n' >> /usr/bin/git && \
    chmod +x /usr/bin/git && \
    chmod +x /usr/local/bin/.git.bin && \
    rm -f /usr/bin/git-receive-pack /usr/bin/git-upload-archive /usr/bin/git-upload-pack

# Replace zsh with a wrapper that sets RALPH_GIT_ALLOWED, then calls real zsh
RUN mv /bin/zsh /bin/zsh-real && \
    printf '#!/bin/sh\n' > /bin/zsh && \
    printf '# Zsh wrapper - sets RALPH_GIT_ALLOWED for git access\n' >> /bin/zsh && \
    printf 'export RALPH_GIT_ALLOWED=1\n' >> /bin/zsh && \
    printf 'exec /bin/zsh-real "$@"\n' >> /bin/zsh && \
    chmod +x /bin/zsh

USER ralph

# Keep container idle - user can run /ralph.sh manually
CMD ["sleep", "infinity"]
