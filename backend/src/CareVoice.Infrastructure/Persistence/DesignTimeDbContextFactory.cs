using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace CareVoice.Infrastructure.Persistence;

public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<CareVoiceDbContext>
{
    public CareVoiceDbContext CreateDbContext(string[] args)
    {
        AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);

        var rawConn = Environment.GetEnvironmentVariable("DATABASE_URL")
            ?? "Host=localhost;Port=5432;Database=carevoice;Username=postgres;Password=postgres";

        var pgConn = DependencyInjection.NormalizePostgresConnectionString(rawConn);

        var optionsBuilder = new DbContextOptionsBuilder<CareVoiceDbContext>();
        optionsBuilder.UseNpgsql(pgConn, b => b.MigrationsAssembly(typeof(CareVoiceDbContext).Assembly.FullName));

        return new CareVoiceDbContext(optionsBuilder.Options);
    }
}
