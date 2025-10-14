"use client";

import { useEffect, useState } from "react";

export function useTicker(intervalMs = 1000): number {
	const [now, setNow] = useState(() => Date.now());

	useEffect(() => {
		if (intervalMs <= 0) {
			return;
		}

		const id = setInterval(() => {
			setNow(Date.now());
		}, intervalMs);

		return () => {
			clearInterval(id);
		};
	}, [intervalMs]);

	return now;
}
