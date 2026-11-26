using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using CareVoice.Application.Interfaces;

namespace CareVoice.Scheduler;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly IServiceProvider _serviceProvider;

    public Worker(ILogger<Worker> logger, IServiceProvider serviceProvider)
    {
        _logger = logger;
        _serviceProvider = serviceProvider;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("CareVoice Missed-Reminder Relay Worker started at: {time}", DateTimeOffset.Now);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = _serviceProvider.CreateScope();
                var relayService = scope.ServiceProvider.GetRequiredService<IMissedReminderRelayService>();

                int processed = await relayService.ProcessOverdueDosesAsync(gracePeriodMinutes: 30);
                if (processed > 0)
                {
                    _logger.LogWarning("Missed-Reminder Relay: Detected and processed {count} overdue dose(s). Notifications generated.", processed);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during missed-reminder relay processing.");
            }

            await Task.Delay(TimeSpan.FromSeconds(60), stoppingToken);
        }
    }
}
