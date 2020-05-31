function [C, IA, IC] = uniqueStruct( A )
% just like unique, except for struct arrays

    hashFn = @(s) sum(typecast(Matdb.DataHash(s, struct('Format', 'uint8')), 'double'));
    aHash = arrayfun(hashFn, A);
    
    [~, IA, IC] = unique(aHash);
    IA = sort(IA); % undo the hash sorting
    C = A(IA);
    
end

