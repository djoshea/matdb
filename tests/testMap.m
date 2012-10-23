function r = testMap(t)

r = t.map(@fn, 'addToDatabase', true, 'entryName', 'result');

end

function r = fn(t)
    r.firstSum = sum(double(t.first));
    r.lastSum = sum(double(t.last));
    r.full = [t.first ' ' t.last];
end



