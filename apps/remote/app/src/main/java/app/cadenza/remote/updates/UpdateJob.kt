package app.cadenza.remote.updates

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import app.cadenza.remote.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class UpdateJob : JobService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var job: Job? = null

    override fun onStartJob(params: JobParameters): Boolean {
        if (!BuildConfig.AUTOMATIC_UPDATES) return false
        job =
            scope.launch {
                var retry = false
                try {
                    if (RemoteUpdater.due(this@UpdateJob)) {
                        val file = RemoteUpdater.checkAndStage(this@UpdateJob)
                        if (file != null) {
                            if (packageManager.canRequestPackageInstalls()) {
                                RemoteUpdater.install(this@UpdateJob, file)
                            } else {
                                InstallResultReceiver.notifyReady(this@UpdateJob, null)
                            }
                        }
                    }
                } catch (_: Exception) {
                    retry = true
                } finally {
                    if (isActive) jobFinished(params, retry)
                }
            }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        job?.cancel()
        return true
    }

    companion object {
        fun schedule(context: Context) {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            if (!BuildConfig.AUTOMATIC_UPDATES || RemoteUpdater.configuration(context).repository.isBlank()) {
                scheduler.cancel(43127)
                return
            }
            val info =
                JobInfo
                    .Builder(43127, ComponentName(context, UpdateJob::class.java))
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_UNMETERED)
                    .setPeriodic(86_400_000, 21_600_000)
                    .setPersisted(true)
                    .build()
            scheduler.schedule(info)
        }
    }
}
