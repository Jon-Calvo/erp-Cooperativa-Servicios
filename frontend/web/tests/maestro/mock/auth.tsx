const g: any = globalThis;
export function useAuth() { return { puede: (m: string, n = 1) => g.__puede ? g.__puede(m, n) : true }; }
