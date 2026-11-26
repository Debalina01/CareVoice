using System.Threading.Tasks;

namespace CareVoice.Application.Interfaces;

public interface IMissedReminderRelayService
{
    Task<int> ProcessOverdueDosesAsync(int gracePeriodMinutes = 30);
}
