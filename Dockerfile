# Use Node.js 22 as the base image
FROM node:22 AS base

# Set environment variables for pnpm
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
ENV SECRET_WORD="TwelveFactor"
# Enable Corepack and install pnpm
RUN npm install -g corepack@latest && corepack enable
RUN corepack prepare pnpm@latest --activate

# Set the working directory inside the container
WORKDIR /app

# Copy package.json and pnpm-lock.yaml to install dependencies
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --frozen-lockfile --prod

# Copy application source code and rename 000.js to index.js
COPY app/src/000.js /app/index.js

# Copy bin directory
COPY app/bin/ /app/bin/

# Set execute permissions for scripts in bin
RUN chmod +x /app/bin/*

# Debugging: List files in /app after copying
RUN ls -l /app

# Expose the port your app runs on
EXPOSE 3000

# Run the app
CMD ["node", "/app/index.js"]
