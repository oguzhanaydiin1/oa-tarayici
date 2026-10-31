#ifndef RUNNER_CRASH_LOG_H_
#define RUNNER_CRASH_LOG_H_

// Çökme kaydı: uygulama beklenmedik şekilde kapanırsa nedeni (hata kodu, hangi bileşende olduğu,
// çağrı yığını) %LOCALAPPDATA%\OA Tarayici\cokme.txt dosyasına yazılır. Uygulama bir sonraki
// açılışta bu dosyayı gösterir.
void InstallCrashLog();

#endif  // RUNNER_CRASH_LOG_H_
