# Étape 1 : build de l'application React avec Vite
FROM node:22-alpine AS build
WORKDIR /app

# On copie d'abord les fichiers de dépendances pour profiter du cache Docker
COPY package*.json ./
RUN npm ci

# Puis le reste du code, et on build
COPY . .
RUN npm run build

# Étape 2 : on sert les fichiers statiques avec Nginx
FROM nginx:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]