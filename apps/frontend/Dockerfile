FROM node:16-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci 

COPY . .

ARG API_URL=http://localhost:5000/api

ENV NODE_OPTIONS="--max-old-space-size=2048"
ENV GENERATE_SOURCEMAP=false

RUN sed -i "s#http://185.230.138.173:5000/api#${API_URL}#g" src/app/api/agent.api.ts \
 && grep -q "${API_URL}" src/app/api/agent.api.ts \
 && npm run build \
 && npm cache clean --force

FROM nginx:alpine AS runtime
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]