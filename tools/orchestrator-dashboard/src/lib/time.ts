export function formatDuration(milliseconds: number): string {
	if (!Number.isFinite(milliseconds) || milliseconds <= 0) {
		return "00:00:00";
	}

	const totalSeconds = Math.floor(milliseconds / 1000);
	const seconds = totalSeconds % 60;
	const totalMinutes = Math.floor(totalSeconds / 60);
	const minutes = totalMinutes % 60;
	const hours = Math.floor(totalMinutes / 60);

	const hh = hours.toString().padStart(2, "0");
	const mm = minutes.toString().padStart(2, "0");
	const ss = seconds.toString().padStart(2, "0");

	return `${hh}:${mm}:${ss}`;
}

export function calculateUptime(
	startedAt: string | null,
	endedAt: string | null,
	now: number,
): string | null {
	if (!startedAt) {
		return null;
	}

	const startMs = new Date(startedAt).getTime();
	if (Number.isNaN(startMs)) {
		return null;
	}

	const endMs = endedAt ? new Date(endedAt).getTime() : now;
	if (Number.isNaN(endMs) || endMs < startMs) {
		return formatDuration(now - startMs);
	}

	return formatDuration(endMs - startMs);
}
