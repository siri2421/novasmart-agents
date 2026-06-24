# Use the official lightweight Node.js Alpine image
FROM node:18-alpine

# Set the working directory inside the container
WORKDIR /app

# Copy package files first to leverage Docker layer caching for dependencies
COPY package*.json ./

# Install production dependencies
RUN npm install --only=production

# Copy the remaining web portal source files (public assets, products, and server)
COPY . .

# Cloud Run injects the PORT environment variable (defaults to 8080)
EXPOSE 8080

# Start the Express server in production mode
CMD ["npm", "start"]
