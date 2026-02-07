# Use a base image with Flutter pre-installed
FROM ghcr.io/cirruslabs/flutter:stable AS build

# Set working directory
WORKDIR /app

# Copy pubspec files first for better caching
COPY po_processor_app/pubspec.yaml po_processor_app/pubspec.lock* ./
RUN flutter pub get

# Copy the rest of the app
COPY po_processor_app/ ./

# Build the Flutter web app
RUN flutter build web --release

# Use a lightweight nginx image to serve the app
FROM nginx:alpine

# Copy built files from Flutter build stage
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy nginx configuration for SPA routing
RUN echo 'server { \
    listen 80; \
    server_name _; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

