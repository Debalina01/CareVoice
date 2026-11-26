# ==============================================================================
# CareVoice API - Multi-Stage Production Dockerfile for Railway
# ==============================================================================

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /app

# Copy solution and project files first to leverage Docker layer caching
COPY CareVoice.sln ./
COPY src/CareVoice.Api/CareVoice.Api.csproj src/CareVoice.Api/
COPY src/CareVoice.Application/CareVoice.Application.csproj src/CareVoice.Application/
COPY src/CareVoice.Domain/CareVoice.Domain.csproj src/CareVoice.Domain/
COPY src/CareVoice.Infrastructure/CareVoice.Infrastructure.csproj src/CareVoice.Infrastructure/
COPY src/CareVoice.Scheduler/CareVoice.Scheduler.csproj src/CareVoice.Scheduler/
COPY tests/CareVoice.Tests/CareVoice.Tests.csproj tests/CareVoice.Tests/

RUN dotnet restore CareVoice.sln

# Copy the rest of the source code
COPY . ./
WORKDIR /app/src/CareVoice.Api
RUN dotnet publish -c Release -o /app/out /p:UseAppHost=false

# ==============================================================================
# Production Runtime Stage (Optimized, lightweight, non-root)
# ==============================================================================
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS runtime
WORKDIR /app

ENV ASPNETCORE_ENVIRONMENT=Production

COPY --from=build /app/out ./

ENTRYPOINT ["dotnet", "CareVoice.Api.dll"]
