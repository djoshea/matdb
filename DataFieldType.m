classdef DataFieldType 
    enumeration
        UnspecifiedField
        ScalarField 
        StringField  
        NumericVectorField
        StringArrayField 
        DateField   % stores a date/time, in string representation 
        DateNumField % stores a date/time, in numeric datenum() representation 
    end
end
