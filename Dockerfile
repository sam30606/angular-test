FROM node:20-alpine AS nodebase

# Install dependencies only when needed
FROM nodebase AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /frontend

# Install dependencies based on the preferred package manager
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm i

# Rebuild the source code only when needed
FROM nodebase AS nodebuilder
WORKDIR /frontend
COPY --from=deps /frontend/node_modules ./node_modules
COPY frontend/ .
RUN npm run build

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS dotnetbuilder
WORKDIR /backend
COPY backend/ .
RUN dotnet restore "backend.csproj"
RUN dotnet build "backend.csproj" -c Release -o /app/build /p:GenerateDocumentationFile=true

FROM dotnetbuilder AS dotnetpublish
RUN dotnet publish "backend.csproj" -c Release -o /app/publish -p:UseAppHost=false --no-restore

FROM nginx:alpine3.20
EXPOSE 8080
EXPOSE 80
# 根據Program.cs裡對於ASPNETCORE_ENVIRONMENT的設定，會決定Swagger的啟用與否
ENV ASPNETCORE_ENVIRONMENT="Release"
# runtime dockerfile有預先設定ASPNETCORE_HTTP_PORTS＝8080，所以如果不設定，預設會是8080
ENV ASPNETCORE_HTTP_PORTS=8080

RUN apk add aspnetcore8-runtime

COPY --from=nodebuilder /frontend/dist/angular-test/browser/ /usr/share/nginx/html
COPY --from=dotnetpublish /backend/app/publish /backend

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY --from=ochinchina/supervisord:latest /usr/local/bin/supervisord /usr/local/bin/supervisord
CMD ["/usr/local/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
