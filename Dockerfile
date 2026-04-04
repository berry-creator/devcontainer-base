FROM debian:bookworm
USER root

#region Add basic packages
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        procps lsof inetutils-ping telnet neovim jq exiftool libxml2-utils zsh \
        git curl wget tar gzip zip unzip \
        ca-certificates sudo locales \
    && apt-get autoremove -y && apt-get clean -y \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen \
    && ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo "${TZ}" > /etc/timezone && dpkg-reconfigure tzdata
#endregion

#region Set up a new user for development
ARG USERNAME=dev
ARG HOME="/home/${USERNAME}"
RUN useradd -g users -s /bin/zsh -m "${USERNAME}" \
    && usermod -aG sudo ${USERNAME} \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

USER ${USERNAME}
#endregion

#region Normal config for nvim, and fix neovim compatible issue with vscode extension, see https://github.com/vscode-neovim/vscode-neovim/wiki/Version-Compatibility-Notes
RUN mkdir -p ${HOME}/.config/nvim \
    && { \
        echo "set shortmess+=s"; \
        echo "imap jj <Esc> "; \
        echo 'let mapleader=" "'; \
        echo "nmap <leader>w :w"; \
        echo "nmap <leader>q :q"; \
        echo "nmap <leader>wq :wq"; \
    } > ${HOME}/.config/nvim/init.vim
#endregion

#region Install oh-my-zsh and some plugins
RUN curl -o- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

SHELL [ "/bin/zsh", "-c" ]
RUN source ~/.zshrc \
    && omz theme set ys \
    && omz plugin enable zsh-syntax-highlighting \
    && omz plugin enable zsh-autosuggestions
#endregion

#region Add additional PATH
USER ${USERNAME}
RUN sed -i '3i\export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH' ~/.zshrc
#endregion

#region Import aliases/functions files if exist
USER ${USERNAME}
RUN echo '[ -f ~/.aliasrc ] && source ~/.aliasrc' >> ~/.zshrc && \
    echo '[ -f ~/.functionrc ] && source ~/.functionrc' >> ~/.zshrc
#endregion

#region Add custom functions
USER ${USERNAME}
RUN cat << 'EOF' >> ~/.zshrc

install_python() {
    set -e
    python_version="$1"

    if command -v python >/dev/null 2>&1; then
        echo "✓ Python already installed, skipping installation"
        return 0
    fi

    echo "▶ Installing Python using pyenv..."

    if ! command -v pyenv >/dev/null 2>&1; then
        echo "pyenv not found, installing pyenv first..."
        curl -fsSL https://pyenv.run | bash
        echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.zshrc
        echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.zshrc
        echo 'eval "$(pyenv init -)"' >> ~/.zshrc
        source ~/.zshrc
    else
        echo "pyenv already installed, skipping pyenv installation"
    fi

    pyenv install ${python_version:-3.12}
    pyenv global ${python_version:-3.12}
    echo "✓ Python installation completed, version: $(python --version)"
}

install_nodejs() {
    set -e
    nodejs_version="$1"
    
    if command -v node >/dev/null 2>&1; then
        echo "✓ Node.js already installed, skipping installation"
        return 0
    fi
    
    echo "▶ Installing Node.js using nvm..."

    if ! command -v nvm >/dev/null 2>&1; then
        echo "nvm not found, installing nvm first..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | PROFILE="/home/${USERNAME}/.zshrc" bash
        echo "" >> ~/.zshrc
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion' >> ~/.zshrc
        source ~/.zshrc
    else
        echo "nvm already installed, skipping nvm installation"
    fi

    if [ -n "${nodejs_version}" ]; then
        nvm install ${nodejs_version}
    else
        nvm install --lts
    fi

    nvm alias default "$(node --version)"
    echo "✓ Node.js installation completed, version: $(node --version)"
}

install_claude() {
  set -e

  if command -v claude >/dev/null 2>&1; then
    echo "✓ Claude CLI already installed, skipping installation"
    return 0
  fi

  echo "▶ Installing Claude CLI..."
  curl -fsSL https://claude.ai/install.sh | bash
  jq '. + {"hasCompletedOnboarding": true}' ~/.claude.json
  echo "✓ Claude CLI ready, type command 'claude' to start using it"
}

install_gemini_cli() {
    set -e

    if ! command -v node >/dev/null 2>&1; then
        echo "Node.js is required to install Gemini CLI. Installing Node.js first..."
        install_nodejs
    fi
    
    if command -v gemini >/dev/null 2>&1; then
        echo "✓ Gemini CLI already installed, skipping installation"
        return 0
    fi
    
    echo "▶ Installing Gemini CLI..."
    npm install -g @google/gemini-cli
    echo "✓ Gemini CLI ready, type command 'gemini' to start using it"
}

install_codex() {
    set -e

    if ! command -v node >/dev/null 2>&1; then
        echo "Node.js is required to install Codex CLI. Installing Node.js first..."
        install_nodejs
    fi

    if command -v codex >/dev/null 2>&1; then
        echo "✓ Codex CLI already installed, skipping installation"
        return 0
    fi

    echo "▶ Installing Codex CLI..."
    npm install -g @openai/codex
    echo "✓ Codex CLI ready, type command 'codex' to start using it"
}
EOF
#endregion

# Switch to dev user
USER ${USERNAME}
WORKDIR /home/${USERNAME}/workspace

ENTRYPOINT [ "/bin/zsh" ]