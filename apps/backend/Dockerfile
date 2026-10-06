FROM mcr.microsoft.com/dotnet/sdk:6.0 AS build
WORKDIR /src

COPY Streetcode/*.sln ./Streetcode/
COPY Streetcode/Streetcode.BLL/*.csproj ./Streetcode/Streetcode.BLL/
COPY Streetcode/Streetcode.DAL/*.csproj ./Streetcode/Streetcode.DAL/
COPY Streetcode/Streetcode.WebApi/*.csproj ./Streetcode/Streetcode.WebApi/

RUN dotnet restore Streetcode/Streetcode.WebApi/Streetcode.WebApi.csproj

COPY . .

RUN dotnet publish Streetcode/Streetcode.WebApi/Streetcode.WebApi.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:6.0 AS runtime
WORKDIR /app

COPY --from=build /app/publish .

EXPOSE 5000
ENV ASPNETCORE_URLS=http://+:5000
ENTRYPOINT ["dotnet", "Streetcode.WebApi.dll"]